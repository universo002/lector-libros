import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'library.dart';
import 'models.dart';
import 'prefs.dart';
import 'segmenter.dart';
import 'translator.dart';

/// Parte del texto que se está leyendo (para resaltarla).
class HL {
  final int para, start, end;
  const HL(this.para, this.start, this.end);
}

/// Motor de lectura con las voces del iPhone.
///
/// Lee frase por frase: así el resaltado va exactamente con lo que se escucha,
/// el ritmo es parejo y se pueden hacer pausas y cambiar el tono en los diálogos.
class ReaderEngine extends ChangeNotifier with WidgetsBindingObserver {
  ReaderEngine._();
  static final ReaderEngine I = ReaderEngine._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<HL?> hl = ValueNotifier(null);
  ReaderAudioHandler? _handler;

  BookMeta? meta;
  BookContent? content;
  List<String?>? translation;

  int idx = 0; // párrafo actual
  int _seg = 0; // frase actual dentro del párrafo
  bool playing = false;
  bool loading = false;
  String? notice;
  int _gen = 0;
  bool _foreground = true;

  Completer<void>? _utterance;
  String _applied = ''; // estilo de voz aplicado (para no repetir llamadas)

  List<Map<String, String>> voices = [];

  DateTime? sleepAt;
  bool sleepEndOfSection = false;
  Timer? _sleepTimer;

  // ------------------------------------------------------------ inicio

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
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
        // Mantiene viva la sesión de audio entre frases (necesario en segundo plano).
        await _tts.autoStopSharedSession(false);
      } catch (_) {}
    }
    await _tts.awaitSpeakCompletion(false);
    _tts.setCompletionHandler(_finishUtterance);
    _tts.setCancelHandler(_finishUtterance);
    _tts.setErrorHandler((dynamic _) => _finishUtterance());
    await loadVoices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
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
    _seg = 0;
    hl.value = null;
    m.opened = DateTime.now();
    Library.I.touch();
    notifyListeners();
    _sync();
  }

  void close() {
    _gen++;
    playing = false;
    _tts.stop();
    meta = null;
    content = null;
    translation = null;
    hl.value = null;
    notifyListeners();
  }

  bool get readingEnglish => meta?.isEnglish == true && meta?.useTranslation != true;

  String textAt(int i) {
    final tr = translation;
    if (meta?.useTranslation == true && tr != null && i < tr.length && tr[i] != null) return tr[i]!;
    return content!.paras[i];
  }

  // ------------------------------------------------------------ controles

  Future<void> play() async {
    if (content == null || playing) return;
    playing = true;
    notifyListeners();
    _sync();
    unawaited(_run());
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _gen++;
    await _tts.stop();
    _finishUtterance();
    loading = false;
    notifyListeners();
    _sync();
    _save();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> jumpTo(int i, {bool? play}) async {
    final c = content;
    if (c == null || c.paras.isEmpty) return;
    final shouldPlay = play ?? playing;
    if (playing) await pause();
    idx = i.clamp(0, c.paras.length - 1);
    _seg = 0;
    hl.value = null;
    _save();
    notifyListeners();
    _sync();
    if (shouldPlay) await this.play();
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

  /// Repite la frase actual (después de cambiar voz, velocidad o idioma).
  Future<void> _restartHere() async {
    _applied = '';
    if (!playing) return;
    await pause();
    await play();
  }

  // ------------------------------------------------------------ lectura frase por frase

  double get _pauseScale => const [0.5, 1.0, 1.8][Prefs.I.pauseLevel];

  Future<String> _textForSpeech(int i) async {
    final m = meta, c = content, tr = translation;
    if (m == null || c == null) return '';
    if (m.useTranslation && tr != null && tr[i] == null) {
      loading = true;
      notifyListeners();
      final t = await Translator.I.translateOne(c.paras[i]);
      if (t != null) tr[i] = t;
      loading = false;
      notifyListeners();
    }
    return textAt(i);
  }

  Future<void> _run() async {
    final gen = ++_gen;
    final c = content;
    if (c == null) return;
    while (playing && gen == _gen) {
      final text = await _textForSpeech(idx);
      if (!playing || gen != _gen) return;
      final segs = segmentText(text);
      final isHeading = c.sections.any((s) => s.start == idx && s.title != 'Inicio');

      for (var k = _seg; k < segs.length; k++) {
        if (!playing || gen != _gen) return;
        _seg = k;
        final s = segs[k];
        hl.value = HL(idx, s.start, s.end);
        _sync();
        await _applyStyle(s.dialogue);
        if (!playing || gen != _gen) return;
        await _say(speechText(s.speak, spanish: !readingEnglish));
        if (!playing || gen != _gen) return;
        // Pausa entre frases: más larga al cambiar entre narración y diálogo.
        final last = k == segs.length - 1;
        if (!last) {
          final change = segs[k + 1].dialogue != s.dialogue;
          await _pause(change ? 0.30 : 0.14);
        }
      }
      if (!playing || gen != _gen) return;

      // Fin del párrafo.
      _seg = 0;
      final nextIdx = idx + 1;
      if (nextIdx >= c.paras.length) {
        playing = false;
        hl.value = null;
        notifyListeners();
        _sync();
        return;
      }
      final timeUp = sleepAt != null && DateTime.now().isAfter(sleepAt!);
      final chapterEnd = sleepEndOfSection && c.sections.any((s) => s.start == nextIdx);
      idx = nextIdx;
      _save();
      notifyListeners();
      if (timeUp || chapterEnd) {
        playing = false;
        hl.value = null;
        clearSleep();
        _sync();
        return;
      }
      final nextIsHeading = c.sections.any((s) => s.start == nextIdx && s.title != 'Inicio');
      await _pause(isHeading || nextIsHeading ? 0.9 : 0.40);
    }
  }

  /// Silencio entre frases. En segundo plano se acorta para que iOS no corte el audio.
  Future<void> _pause(double seconds) async {
    if (!_foreground) return;
    final ms = (seconds * _pauseScale * 1000 / Prefs.I.speed.clamp(0.6, 1.8)).round();
    if (ms > 0) await Future.delayed(Duration(milliseconds: ms));
  }

  Future<void> _say(String text) async {
    if (text.trim().isEmpty) return;
    final done = Completer<void>();
    _utterance = done;
    await _tts.speak(text);
    // Por si el iPhone no avisa que terminó: tiempo máximo razonable.
    final limit = Duration(milliseconds: 4000 + (text.length * 180 / Prefs.I.speed).round());
    await done.future.timeout(limit, onTimeout: () {});
    if (identical(_utterance, done)) _utterance = null;
  }

  void _finishUtterance() {
    final u = _utterance;
    if (u != null && !u.isCompleted) u.complete();
  }

  // ------------------------------------------------------------ voz, tono y velocidad

  double _rate(double s) {
    // En iPhone 0.5 es la velocidad «normal» de Apple, que para leer libros es rápida.
    // Acá 1.0× equivale a 0.45, más pausado y claro.
    final r = s <= 1 ? 0.45 - (1 - s) * 0.30 : 0.45 + (s - 1) * 0.28;
    return r.clamp(0.25, 0.75).toDouble();
  }

  Future<void> _applyStyle(bool dialogue) async {
    final p = Prefs.I;
    String key;
    Map<String, String>? voice;
    double pitch = 1.0;
    double rate = _rate(p.speed);

    if (readingEnglish) {
      key = 'en';
    } else if (dialogue && p.dialogueMode == DialogueMode.otraVoz && dialogueVoice != null) {
      voice = dialogueVoice;
      rate = _rate(p.speed * 0.97);
      key = 'dv:${voice!['name']}';
    } else if (dialogue && p.dialogueMode == DialogueMode.tono) {
      voice = currentVoice;
      pitch = 1.14;
      rate = _rate(p.speed * 0.95);
      key = 'dt';
    } else {
      voice = currentVoice;
      key = 'n';
    }
    key = '$key|${p.speed}|${voice?['name']}';
    if (key == _applied) return;
    _applied = key;

    if (readingEnglish) {
      final en = englishVoice;
      if (en != null) {
        await _tts.setVoice({'name': en['name']!, 'locale': en['locale']!});
      } else {
        await _tts.setLanguage('en-US');
      }
    } else if (voice != null) {
      await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    } else {
      await _tts.setLanguage('es-ES');
    }
    await _tts.setPitch(pitch);
    await _tts.setSpeechRate(rate);
  }

  Future<void> loadVoices() async {
    try {
      final raw = await _tts.getVoices;
      final list = <Map<String, String>>[];
      for (final v in (raw as List)) {
        if (v is! Map) continue;
        final m = {for (final e in v.entries) e.key.toString(): e.value.toString()};
        final loc = (m['locale'] ?? '').toLowerCase();
        if (loc.startsWith('es') || loc.startsWith('en')) list.add(m);
      }
      list.sort((a, b) {
        final la = (a['locale'] ?? '').toLowerCase().startsWith('es') ? 0 : 1;
        final lb = (b['locale'] ?? '').toLowerCase().startsWith('es') ? 0 : 1;
        if (la != lb) return la - lb;
        final r = _rank(a).compareTo(_rank(b));
        return r != 0 ? r : (a['name'] ?? '').compareTo(b['name'] ?? '');
      });
      voices = list;
      notifyListeners();
    } catch (_) {}
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  static int _rank(Map<String, String> v) {
    final q = (v['quality'] ?? '').toLowerCase();
    final n = _norm('${v['name']} ${v['identifier'] ?? ''}');
    if (q.contains('premium') || n.contains('premium')) return 0;
    if (q.contains('enhanced') || n.contains('enhanced') || n.contains('mejorada')) return 1;
    return 2;
  }

  static String quality(Map<String, String> v) => const ['Premium', 'Mejorada', 'Estándar'][_rank(v)];

  List<Map<String, String>> get spanishVoices =>
      voices.where((v) => (v['locale'] ?? '').toLowerCase().startsWith('es')).toList();

  Map<String, String>? _find(String? name, String? locale) {
    if (name == null) return null;
    for (final v in voices) {
      if (v['name'] == name && v['locale'] == locale) return v;
    }
    return null;
  }

  /// La voz elegida, o la mejor «Mónica» disponible, o la mejor voz en español.
  Map<String, String>? get currentVoice {
    final chosen = _find(Prefs.I.voiceName, Prefs.I.voiceLocale);
    if (chosen != null) return chosen;
    final es = spanishVoices;
    for (final v in es) {
      if (_norm(v['name'] ?? '').contains('monica')) return v;
    }
    return es.isNotEmpty ? es.first : null;
  }

  Map<String, String>? get dialogueVoice => _find(Prefs.I.dialogueVoiceName, Prefs.I.dialogueVoiceLocale);

  Map<String, String>? get englishVoice {
    for (final v in voices) {
      if ((v['locale'] ?? '').toLowerCase().startsWith('en')) return v;
    }
    return null;
  }

  String get currentVoiceLabel {
    final v = currentVoice;
    if (v == null) return 'Voz del iPhone';
    final q = quality(v);
    return q == 'Estándar' ? v['name']! : '${v['name']} · $q';
  }

  /// Escucha cómo suena una voz.
  Future<void> preview(Map<String, String> v, {bool dialogue = false}) async {
    if (playing) await pause();
    _applied = '';
    await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    await _tts.setPitch(dialogue && Prefs.I.dialogueMode == DialogueMode.tono ? 1.14 : 1.0);
    await _tts.setSpeechRate(_rate(Prefs.I.speed));
    final sample = (v['locale'] ?? '').toLowerCase().startsWith('en')
        ? 'Hello. This is how I sound reading your book.'
        : (dialogue ? '¿De verdad creés que vamos a llegar a tiempo?' : 'Hola. Así sueno cuando leo tu libro, frase por frase.');
    await _tts.speak(sample);
  }

  Future<void> previewDialogue() async {
    if (playing) await pause();
    _applied = '';
    await _applyStyle(false);
    await _say('Ella lo miró en silencio y le preguntó:');
    await Future.delayed(const Duration(milliseconds: 300));
    await _applyStyle(true);
    await _say('¿De verdad creés que vamos a llegar a tiempo?');
    _applied = '';
  }

  // ------------------------------------------------------------ ajustes

  Future<void> setSpeed(double s) async {
    Prefs.I.setSpeed(s);
    notifyListeners();
    await _restartHere();
  }

  Future<void> voicesChanged() async {
    notifyListeners();
    await _restartHere();
  }

  void setUseTranslation(bool v) {
    final m = meta;
    if (m == null) return;
    m.useTranslation = v;
    Library.I.touch();
    hl.value = null;
    _seg = 0;
    notifyListeners();
    _restartHere();
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

  int _minutesFor(int chars) => (chars / (800 * Prefs.I.speed)).round();

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

  String get sectionTitle {
    final c = content;
    if (c == null || c.sections.isEmpty) return '';
    return c.sections[c.sectionOf(idx)].title;
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
    final art = m.hasCover ? Uri.file(Library.I.coverPath(m.id)) : null;
    h.sync(playing, c.sections[c.sectionOf(idx)].title, m.title, m.author, art);
  }
}

/// Controles de la pantalla bloqueada, el Centro de control y los auriculares.
class ReaderAudioHandler extends BaseAudioHandler {
  String _lastKey = '';

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

  void sync(bool playing, String section, String book, String author, Uri? art) {
    final key = '$playing|$section|$book';
    if (key == _lastKey) return;
    _lastKey = key;
    mediaItem.add(MediaItem(
      id: book,
      title: section,
      album: book,
      artist: author.isEmpty ? book : author,
      artUri: art,
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
