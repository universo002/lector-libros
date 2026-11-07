import AVFoundation
import Flutter
import UIKit

/// Motor de voz de Lector: usa AVSpeechSynthesizer con una cola de frases.
/// Las frases se encadenan sin cortes y las pausas las hace el propio iPhone,
/// así funciona igual con la pantalla bloqueada.
public class LectorTtsPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  private let synth = AVSpeechSynthesizer()
  private var channel: FlutterMethodChannel?
  private var ids: [AVSpeechUtterance: Int] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lector_tts", binaryMessenger: registrar.messenger())
    let instance = LectorTtsPlugin()
    instance.channel = channel
    instance.synth.delegate = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.observeSession()
  }

  // MARK: - Llamadas desde Dart

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getVoices":
      result(voices())
    case "enqueue":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: Any]] else {
        result(FlutterError(code: "args", message: "Faltan las frases", details: nil))
        return
      }
      prepareSession()
      for item in items {
        enqueue(item)
      }
      result(true)
    case "stop":
      ids.removeAll()
      synth.stopSpeaking(at: .immediate)
      result(true)
    case "pause":
      result(synth.pauseSpeaking(at: .immediate))
    case "resume":
      prepareSession()
      result(synth.continueSpeaking())
    case "isSpeaking":
      result(synth.isSpeaking)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func enqueue(_ item: [String: Any]) {
    guard let text = item["text"] as? String, let id = item["id"] as? Int else { return }
    let u = AVSpeechUtterance(string: text)
    if let vid = item["voice"] as? String, !vid.isEmpty, let v = AVSpeechSynthesisVoice(identifier: vid) {
      u.voice = v
    } else if let lang = item["lang"] as? String {
      u.voice = AVSpeechSynthesisVoice(language: lang)
    }
    if let r = item["rate"] as? Double {
      u.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, Float(r)))
    }
    if let p = item["pitch"] as? Double { u.pitchMultiplier = Float(p) }
    if let vol = item["volume"] as? Double { u.volume = Float(vol) }
    if let pre = item["pre"] as? Double { u.preUtteranceDelay = pre }
    if let post = item["post"] as? Double { u.postUtteranceDelay = post }
    ids[u] = id
    synth.speak(u)
  }

  private func voices() -> [[String: Any]] {
    return AVSpeechSynthesisVoice.speechVoices().map { v in
      var gender = 0
      if #available(iOS 13.0, *) {
        gender = v.gender.rawValue
      }
      return [
        "id": v.identifier,
        "name": v.name,
        "lang": v.language,
        "quality": v.quality.rawValue,
        "gender": gender,
      ]
    }
  }

  // MARK: - Sesión de audio

  private func prepareSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP, .allowAirPlay])
      try session.setActive(true)
    } catch {
      // Si falla, el iPhone usa la configuración por defecto.
    }
  }

  private func observeSession() {
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(onInterruption(_:)),
                   name: AVAudioSession.interruptionNotification, object: nil)
    nc.addObserver(self, selector: #selector(onRouteChange(_:)),
                   name: AVAudioSession.routeChangeNotification, object: nil)
  }

  /// Llamadas, alarmas, Siri: avisa a Dart para pausar y, si corresponde, retomar.
  @objc private func onInterruption(_ n: Notification) {
    guard let info = n.userInfo,
          let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    var began = false
    var resume = false
    if type == .began {
      began = true
    } else if let o = info[AVAudioSessionInterruptionOptionKey] as? UInt {
      resume = AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume)
    }
    DispatchQueue.main.async {
      self.channel?.invokeMethod("onInterrupt", arguments: ["began": began, "resume": resume])
    }
  }

  /// Si se desconectan los auriculares, se pausa (como cualquier app de audio).
  @objc private func onRouteChange(_ n: Notification) {
    guard let info = n.userInfo,
          let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
    if reason == .oldDeviceUnavailable {
      DispatchQueue.main.async {
        if self.synth.isSpeaking {
          self.synth.pauseSpeaking(at: .immediate)
        }
        self.channel?.invokeMethod("onRouteLost", arguments: nil)
      }
    }
  }

  // MARK: - Avisos del sintetizador

  private func send(_ method: String, _ u: AVSpeechUtterance, _ extra: [String: Any]?, remove: Bool) {
    DispatchQueue.main.async {
      guard let id = self.ids[u] else { return }
      if remove {
        self.ids.removeValue(forKey: u)
      }
      var args: [String: Any] = ["id": id]
      if let e = extra {
        for (k, v) in e {
          args[k] = v
        }
      }
      self.channel?.invokeMethod(method, arguments: args)
    }
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    send("onStart", utterance, nil, remove: false)
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    send("onFinish", utterance, nil, remove: true)
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      self.ids.removeValue(forKey: utterance)
    }
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                willSpeakRangeOfSpeechString characterRange: NSRange,
                                utterance: AVSpeechUtterance) {
    send("onRange", utterance, ["loc": characterRange.location, "len": characterRange.length], remove: false)
  }
}
