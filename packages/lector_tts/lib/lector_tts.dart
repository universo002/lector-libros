import 'package:flutter/services.dart';

/// Una voz instalada en el iPhone.
class NativeVoice {
  final String id;
  final String name;
  final String lang;
  final int quality; // 1 estándar, 2 mejorada, 3 premium
  final int gender; // 0 sin dato, 1 hombre, 2 mujer

  const NativeVoice({
    required this.id,
    required this.name,
    required this.lang,
    required this.quality,
    required this.gender,
  });

  String get qualityLabel => quality >= 3 ? 'Premium' : (quality == 2 ? 'Mejorada' : 'Estándar');
}

/// Una frase para la cola de voz.
class Utterance {
  final int id;
  final String text;
  final String? voiceId;
  final String lang;
  final double rate;
  final double pitch;
  final double volume;
  final double pre;
  final double post;

  const Utterance({
    required this.id,
    required this.text,
    this.voiceId,
    this.lang = 'es-ES',
    this.rate = 0.46,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.pre = 0,
    this.post = 0,
  });

  Map<String, Object> toMap() => {
        'id': id,
        'text': text,
        'voice': voiceId ?? '',
        'lang': lang,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'pre': pre,
        'post': post,
      };
}

/// Puente con el motor de voz nativo del iPhone.
class LectorTts {
  LectorTts._();

  static const MethodChannel _ch = MethodChannel('lector_tts');

  static void Function(int id)? onStart;
  static void Function(int id)? onFinish;
  static void Function(int id, int loc, int len)? onRange;
  static void Function(bool began, bool resume)? onInterrupt;
  static void Function()? onRouteLost;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      final args = call.arguments;
      final m = args is Map ? args : const {};
      switch (call.method) {
        case 'onStart':
          onStart?.call((m['id'] as num).toInt());
          break;
        case 'onFinish':
          onFinish?.call((m['id'] as num).toInt());
          break;
        case 'onRange':
          onRange?.call((m['id'] as num).toInt(), (m['loc'] as num).toInt(), (m['len'] as num).toInt());
          break;
        case 'onInterrupt':
          onInterrupt?.call(m['began'] == true, m['resume'] == true);
          break;
        case 'onRouteLost':
          onRouteLost?.call();
          break;
      }
      return null;
    });
  }

  static Future<List<NativeVoice>> voices() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getVoices');
      if (raw == null) return [];
      return raw.whereType<Map>().map((m) {
        return NativeVoice(
          id: (m['id'] ?? '').toString(),
          name: (m['name'] ?? '').toString(),
          lang: (m['lang'] ?? '').toString(),
          quality: ((m['quality'] ?? 1) as num).toInt(),
          gender: ((m['gender'] ?? 0) as num).toInt(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> enqueue(List<Utterance> items) async {
    if (items.isEmpty) return;
    await _ch.invokeMethod('enqueue', {'items': items.map((e) => e.toMap()).toList()});
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<bool> pause() async {
    try {
      return (await _ch.invokeMethod<bool>('pause')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> resume() async {
    try {
      return (await _ch.invokeMethod<bool>('resume')) ?? false;
    } catch (_) {
      return false;
    }
  }
}
