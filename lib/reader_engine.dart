import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'library.dart';
import 'models.dart';
import 'prefs.dart';
import 'translator.dart';

class WordRange {
  final int para, start, end;
  const WordRange(this.para, this.start, this.end);
}

/// Motor de lectura: maneja la voz, el párrafo actual, el temporizador
/// y los controles de la pantalla bloqueada.
class ReaderEngine extends ChangeNotifier {
  ReaderEngine._();
  static final ReaderEngine I = ReaderEngine._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<WordRange?> word = ValueNotifier(null);
  ReaderAudioHandler? _handler;

  BookMeta? meta;
  BookContent? content;
  List<String?>? translation;

  int idx = 0;
  bool playing = false;
  int _offset = 0; // desde qué letra del párrafo empezó a hablar
  int _lastWordStart = 0;
  int _resumeAt = 0;
  int _gen = 0;

  DateTime? sleepAt;
  bool sleepEndOfSection = false;
  Timer? _sleepTimer;

  List<Map<String, String>> voices = [];

  // ------------------------------------------------------------ inicio

  Future<void> init() async {
    if (Platform.isIOS) {
      try {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
        // Mantiene viva la sesión de audio entre párrafos (clave para el
        // segundo plano). Si tu versión de flutter_tts no la tiene, borrá esta línea.
        await _tts.autoStopSharedSession(false);
      } catch (_) {}
    }
    await _tts.awaitSpeakCompletion(false);
    _tts.setProgressHandler((String text, int start, int end, String w) {
      _lastWordStart = _offset + start;
      word.value = WordRange(idx, _offset + start, _offset + end);
    });
    _tts.setCompletionHandler(_onDone);
    _tts.setErrorHandler((dynamic _) {
      if (playing) _onDone();
    });
    await _applyRate();
    await loadVoices();
    await _applyVoice();
  }

  void attachHandler(ReaderAudioHandler h) {
    _handler = h;
    _sync();
  }

  // ------------------------------------------------------------ libro

  Future<void> open(BookMeta m) async {
    if (meta?.id == m.id && content != null) {
      m.opened = DateTime.now();
      Library.I.touch();
      return;
    }
    if (playing) await pause();
    final c = await Library.I.content(m.id);
    final tr = await Library.I.translation(m.id);
    meta = m;
    content = c;
    translation = tr;
    idx = c.paras.isEmpty ? 0 : m.position.clamp(0, c.paras.length - 1);
    _resumeAt = 0;
    word.value = null;
    m.opened = DateTime.now();
    Library.I.touch();
    notifyListeners();
    _sync();
    if (m.useTranslation && tr != null) unawaited(Translator.I.ensureModel());
  }

  void close() {
    _gen++;
    playing = false;
    _tts.stop();
    meta = null;
    content = null;
    translation = null;
    word.value = null;
    notifyListeners();
  }

  String textAt(int i) {
    final c = content!;
    final tr = translation;
    if (meta?.useTranslation == true && tr != null && i < tr.length && tr[i] != null) return tr[i]!;
    return c.paras[i];
  }

  // ------------------------------------------------------------ voz

  Future<void> _speak() async {
    final c = content, m = meta;
    if (c == null || m == null) return;
    final gen = ++_gen;
    var text = textAt(idx);
    final tr = translation;
    if (m.useTranslation && tr != null && tr[idx] == null) {
      // Si el párrafo todavía no está traducido, lo traduce al momento.
      final t = await Translator.I.translateOne(c.paras[idx]);
      if (t != null) {
        tr[idx] = t;
        text = t;
      }
      if (gen != _gen || !playing) return;
    }
    final from = _resumeAt.clamp(0, text.length);
    _resumeAt = 0;
    _offset = from;
    _lastWordStart = from;
    final say = text.substring(from);
    word.value = WordRange(idx, from, from);
    notifyListeners();
    _sync();
    if (say.trim().isEmpty) {
      _onDone();
      return;
    }
    await _tts.speak(say);
  }

  void _onDone() {
    final c = content;
    if (!playing || c == null) return;
    final next = idx + 1;
    if (next >= c.paras.length) {
      playing = false;
      _resumeAt = 0;
      notifyListeners();
      _sync();
      return;
    }
    final timeUp = sleepAt != null && DateTime.now().isAfter(sleepAt!);
    final chapterEnd = sleepEndOfSection && c.sections.any((s) => s.start == next);
    idx = next;
    _save();
    if (timeUp || chapterEnd) {
      playing = false;
      _resumeAt = 0;
      word.value = null;
      clearSleep();
      _sync();
      return;
    }
    _speak();
  }

  Future<void> play() async {
    if (content == null || playing) return;
    playing = true;
    await _speak();
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _gen++;
    _resumeAt = _lastWordStart;
    await _tts.stop();
    notifyListeners();
    _sync();
    _save();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> jumpTo(int i, {bool? play}) async {
    final c = content;
    if (c == null || c.paras.isEmpty) return;
    final shouldPlay = play ?? playing;
    _gen++;
    if (playing) await _tts.stop();
    idx = i.clamp(0, c.paras.length - 1);
    _resumeAt = 0;
    word.value = null;
    playing = shouldPlay;
    _save();
    if (shouldPlay) {
      await _speak();
    } else {
      notifyListeners();
      _sync();
    }
  }

  Future<void> next() => jumpTo(idx + 1);
  Future<void> prev() => jumpTo(idx - 1);

  Future<void> skipSection(int dir) async {
    final c = content;
    if (c == null) return;
    final s = c.sectionOf(idx);
    if (dir < 0 && idx > c.sections[s].start + 2) return jumpTo(c.sections[s].start);
    final t = (s + dir).clamp(0, c.sections.length - 1);
    return jumpTo(c.sections[t].start);
  }

  Future<void> _restartHere() async {
    if (!playing) return;
    _resumeAt = _lastWordStart;
    _gen++;
    await _tts.stop();
    await _speak();
  }

  // ------------------------------------------------------------ ajustes

  Future<void> _applyRate() async {
    final s = Prefs.I.speed;
    // En iPhone 0.5 es la velocidad normal y 1.0 es el máximo.
    final double r = Platform.isIOS ? (s >= 1 ? 0.5 + (s - 1) * 0.25 : 0.5 - (1 - s) * 0.4) : s;
    await _tts.setSpeechRate(r.clamp(0.1, Platform.isIOS ? 1.0 : 3.0).toDouble());
  }

  Future<void> setSpeed(double s) async {
    Prefs.I.setSpeed(s);
    await _applyRate();
    notifyListeners();
    await _restartHere();
  }

  Future<void> loadVoices() async {
    try {
      final raw = await _tts.getVoices;
      final list = <Map<String, String>>[];
      for (final v in (raw as List)) {
        if (v is! Map) continue;
        final m = {for (final e in v.entries) e.key.toString(): e.value.toString()};
        if ((m['locale'] ?? '').toLowerCase().startsWith('es')) list.add(m);
      }
      int rank(Map<String, String> v) {
        final q = (v['quality'] ?? '').toLowerCase();
        final spain = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-') == 'es-es' ? 0 : 10;
        final qq = q.contains('premium') ? 0 : (q.contains('enhanced') ? 1 : 2);
        return spain + qq;
      }

      list.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : (a['name'] ?? '').compareTo(b['name'] ?? '');
      });
      voices = list;
      notifyListeners();
    } catch (_) {}
  }

  Map<String, String>? get currentVoice {
    final n = Prefs.I.voiceName;
    for (final v in voices) {
      if (v['name'] == n && v['locale'] == Prefs.I.voiceLocale) return v;
    }
    return null;
  }

  Future<void> _applyVoice() async {
    final v = currentVoice ?? (voices.isNotEmpty ? voices.first : null);
    if (v != null) {
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    } else {
      await _tts.setLanguage('es-ES');
    }
  }

  Future<void> setVoice(Map<String, String> v, {bool preview = true}) async {
    Prefs.I.setVoice(v['name']!, v['locale']!);
    await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    notifyListeners();
    if (playing) {
      await _restartHere();
    } else if (preview) {
      await _tts.stop();
      await _tts.speak('Hola, así sueno leyendo tu libro.');
    }
  }

  void setUseTranslation(bool v) {
    final m = meta;
    if (m == null) return;
    m.useTranslation = v;
    Library.I.touch();
    word.value = null;
    notifyListeners();
    if (v) unawaited(Translator.I.ensureModel());
    if (playing) {
      _resumeAt = 0;
      _lastWordStart = 0;
      _restartHere();
    }
  }

  // ------------------------------------------------------------ temporizador

  void setSleepMinutes(int m) {
    clearSleep();
    sleepAt = DateTime.now().add(Duration(minutes: m));
    _sleepTimer = Timer(Duration(minutes: m), () {
      pause();
      clearSleep();
    });
    notifyListeners();
  }

  void setSleepEndOfSection() {
    clearSleep();
    sleepEndOfSection = true;
    notifyListeners();
  }

  void clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    sleepEndOfSection = false;
    notifyListeners();
  }

  bool get sleepActive => sleepAt != null || sleepEndOfSection;

  void refresh() => notifyListeners();

  // ------------------------------------------------------------ marcadores

  void toggleBookmark(int i) {
    final m = meta;
    if (m == null) return;
    if (m.bookmarks.contains(i)) {
      m.bookmarks.remove(i);
    } else {
      m.bookmarks.add(i);
      m.bookmarks.sort();
    }
    Library.I.touch();
    notifyListeners();
  }

  // ------------------------------------------------------------ tiempos

  int _minutesFor(int chars) => (chars / (950 * Prefs.I.speed)).round();

  int get remainingMinutes {
    final c = content;
    if (c == null) return 0;
    return _minutesFor(c.prefix.last - c.prefix[idx]);
  }

  int get sectionRemainingMinutes {
    final c = content;
    if (c == null) return 0;
    final end = c.sectionEnd(c.sectionOf(idx));
    return _minutesFor(c.prefix[end] - c.prefix[idx]);
  }

  // ------------------------------------------------------------ interno

  void _save() {
    final m = meta;
    if (m == null) return;
    m.position = idx;
    Library.I.touch();
  }

  void _sync() {
    final m = meta, c = content, h = _handler;
    if (m == null || c == null || h == null || c.sections.isEmpty) return;
    h.sync(playing, c.sections[c.sectionOf(idx)].title, m.title, m.author);
  }
}

/// Controles de la pantalla bloqueada, el Centro de control y los auriculares.
class ReaderAudioHandler extends BaseAudioHandler {
  @override
  Future<void> play() => ReaderEngine.I.play();

  @override
  Future<void> pause() => ReaderEngine.I.pause();

  @override
  Future<void> stop() => ReaderEngine.I.pause();

  @override
  Future<void> skipToNext() => ReaderEngine.I.next();

  @override
  Future<void> skipToPrevious() => ReaderEngine.I.prev();

  void sync(bool playing, String section, String book, String author) {
    mediaItem.add(MediaItem(
      id: book,
      title: section,
      album: book,
      artist: author.isEmpty ? book : author,
    ));
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
    ));
  }
}
