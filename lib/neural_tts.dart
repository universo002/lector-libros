import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Una frase para sintetizar con una voz concreta.
class SynthItem {
  final String text;
  final String model;
  final String tokens;
  final String dataDir;
  final int sid;
  final double pauseAfter; // segundos de silencio después de la frase

  const SynthItem({
    required this.text,
    required this.model,
    required this.tokens,
    required this.dataDir,
    required this.sid,
    required this.pauseAfter,
  });

  Map<String, Object> toMap() => {
        'text': text,
        'model': model,
        'tokens': tokens,
        'dataDir': dataDir,
        'sid': sid,
        'pause': pauseAfter,
      };
}

/// Resultado: un archivo WAV y en qué segundo empieza y termina cada frase.
class SynthResult {
  final String path;
  final List<double> starts;
  final List<double> ends;
  final double duration;
  const SynthResult(this.path, this.starts, this.ends, this.duration);
}

/// Genera el audio con voces Piper en un hilo aparte, para que la app no se trabe.
class NeuralTts {
  NeuralTts._();
  static final NeuralTts I = NeuralTts._();

  SendPort? _send;
  Future<void>? _starting;
  final Map<int, Completer<SynthResult>> _pending = {};
  int _nextId = 0;

  Future<void> _ensure() {
    if (_send != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final rp = ReceivePort();
    final ready = Completer<void>();
    rp.listen((dynamic msg) {
      if (msg is SendPort) {
        _send = msg;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (msg is Map) {
        final id = msg['id'] as int;
        final c = _pending.remove(id);
        if (c == null) return;
        if (msg['err'] != null) {
          c.completeError(Exception(msg['err'] as String));
        } else {
          c.complete(SynthResult(
            msg['path'] as String,
            (msg['starts'] as List).map((e) => (e as num).toDouble()).toList(),
            (msg['ends'] as List).map((e) => (e as num).toDouble()).toList(),
            (msg['dur'] as num).toDouble(),
          ));
        }
      }
    });
    await Isolate.spawn(_worker, rp.sendPort);
    await ready.future;
  }

  Future<SynthResult> synth(List<SynthItem> items, double speed, String outPath) async {
    await _ensure();
    final id = _nextId++;
    final c = Completer<SynthResult>();
    _pending[id] = c;
    _send!.send({
      'id': id,
      'items': items.map((e) => e.toMap()).toList(),
      'speed': speed,
      'out': outPath,
    });
    return c.future;
  }
}

void _worker(SendPort main) {
  so.initBindings();
  final rp = ReceivePort();
  main.send(rp.sendPort);
  final engines = <String, so.OfflineTts>{};

  so.OfflineTts engineFor(Map it) {
    final key = it['model'] as String;
    final cached = engines[key];
    if (cached != null) return cached;
    if (engines.length >= 3) {
      final first = engines.keys.first;
      engines.remove(first)?.free();
    }
    final vits = so.OfflineTtsVitsModelConfig(
      model: key,
      tokens: it['tokens'] as String,
      dataDir: it['dataDir'] as String,
    );
    final modelConfig = so.OfflineTtsModelConfig(
      vits: vits,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    final config = so.OfflineTtsConfig(model: modelConfig);
    final tts = so.OfflineTts(config);
    engines[key] = tts;
    return tts;
  }

  rp.listen((dynamic msg) {
    final m = msg as Map;
    final id = m['id'] as int;
    try {
      final items = (m['items'] as List).cast<Map>();
      final speed = (m['speed'] as num).toDouble();
      final chunks = <Float32List>[];
      final starts = <double>[];
      final ends = <double>[];
      var total = 0;
      var sr = 22050;
      for (final it in items) {
        final tts = engineFor(it);
        final audio = tts.generate(text: it['text'] as String, sid: it['sid'] as int, speed: speed);
        sr = audio.sampleRate;
        final samples = audio.samples;
        starts.add(total / sr);
        chunks.add(samples);
        total += samples.length;
        ends.add(total / sr);
        final pause = ((it['pause'] as num).toDouble() * sr / speed).round();
        if (pause > 0) {
          chunks.add(Float32List(pause));
          total += pause;
        }
      }
      final all = Float32List(total);
      var o = 0;
      for (final c in chunks) {
        all.setAll(o, c);
        o += c.length;
      }
      final out = m['out'] as String;
      File(out).writeAsBytesSync(_wav(all, sr));
      main.send({'id': id, 'path': out, 'starts': starts, 'ends': ends, 'dur': total / sr});
    } catch (e) {
      main.send({'id': id, 'err': e.toString()});
    }
  });
}

Uint8List _wav(Float32List s, int sr) {
  final n = s.length;
  final bd = ByteData(44 + n * 2);
  void str(int o, String v) {
    for (var i = 0; i < v.length; i++) {
      bd.setUint8(o + i, v.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  bd.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sr, Endian.little);
  bd.setUint32(28, sr * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  str(36, 'data');
  bd.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    var v = s[i];
    if (v > 1) v = 1;
    if (v < -1) v = -1;
    bd.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return bd.buffer.asUint8List();
}
