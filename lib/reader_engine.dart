import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'models.dart';
import 'neural_tts.dart';
import 'prefs.dart';
import 'segmenter.dart';
import 'translator.dart';
import 'voices.dart';

/// Parte del texto que se está leyendo (para resaltarla).
class HL {
  final int para, start, end;
  const HL(this.para, this.start, this.end);
}

class _Para {
  final int idx;
  final String text;
  final List<Seg> spoken;
  final SynthResult? res;
  const _Para(this.idx, this.text, this.spoken, this.res);
}

/// Motor de lectura: voces naturales (Piper) con respaldo en la voz del iPhone.
class ReaderEngine extends ChangeNotifier {
  ReaderEngine._();
  static final ReaderEngine I = ReaderEngine._();

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _preview = AudioPlayer();
  final ValueNotifier<HL?> hl = ValueNotifier(null);
  ReaderAudioHandler? _handler;

  BookMeta? meta;
  BookContent? content;
  List<String?>? translation;

  int idx = 0;
  bool playing = false;
  bool loading = false;
  String? notice; // mensaje para mostrar una vez
  int _gen = 0;

  // Voces naturales
  late String _audioDir;
  final Map<int, Future<_Para?>> _cache = {};
  String _cacheKey = '';
  _Para? _cur;
  int _fileSeq = 0;
  int _completedFor = -1;
  bool _forceSystem = false;

  // Voz del iPhone
  int _offset = 0;
  int _lastWordStart = 0;
  int _resumeAt = 0;
  List<Map<String, String>> sysVoices = [];

  // Temporizador
  DateTime? sleepAt;
  bool sleepEndOfSection = false;
  Timer? _sleepTimer;

  // ------------------------------------------------------------ inicio

  Future<void> init() async {
    final tmp = await getTemporaryDirectory();
    _audioDir = '${tmp.path}/lector_audio';
    final d = Directory(_audioDir);
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (_) {}

    _player.positionStream.listen(_onPosition);
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onNeuralDone();
    });

    await _initSystemVoice();
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
    await _stopAll();
    final c = await Library.I.content(m.id);
    final tr = await Library.I.translation(m.id);
    meta = m;
    content = c;
    translation = tr;
    idx = c.paras.isEmpty ? 0 : m.position.clamp(0, c.paras.length - 1);
    _resetAudio();
    hl.value = null;
    m.opened = DateTime.now();
    Library.I.touch();
    notifyListeners();
    _sync();
  }

  void close() {
    _gen++;
    playing = false;
    _stopAll();
    _resetAudio();
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

  // ------------------------------------------------------------ qué voz usar

  VoiceInfo? get narratorVoice => voiceById(readingEnglish ? Prefs.I.english : Prefs.I.narrator);

  VoiceInfo? get dialogueVoiceInfo {
    if (readingEnglish || !Prefs.I.dialogueVoice) return null;
    final v = voiceById(Prefs.I.dialogue);
    return Voices.I.isReady(v) ? v : null;
  }

  bool get usingNeural => !Prefs.I.useSystemVoice && !_forceSystem && Voices.I.isReady(narratorVoice);

  String get currentVoiceLabel {
    if (usingNeural) {
      final n = narratorVoice!;
      final d = dialogueVoiceInfo;
      return d == null || d.id == n.id ? n.name : '${n.name} + ${d.name}';
    }
    return currentSystemVoice?['name'] ?? 'Voz del iPhone';
  }

  // ------------------------------------------------------------ controles

  Future<void> play() async {
    if (content == null || playing) return;
    playing = true;
    notifyListeners();
    if (usingNeural) {
      final cur = _cur;
      if (cur != null && cur.idx == idx && _cacheKey == _key() && _player.audioSource != null) {
        unawaited(_player.play());
        _sync();
        return;
      }
      await _playNeural();
    } else {
      await _speakSystem();
    }
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _gen++;
    if (_player.playing) await _player.pause();
    _resumeAt = _lastWordStart;
    await _tts.stop();
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
    _gen++;
    await _stopAll();
    idx = i.clamp(0, c.paras.length - 1);
    _cur = null;
    _resumeAt = 0;
    hl.value = null;
    playing = false;
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

  /// Vuelve a empezar el párrafo actual (después de cambiar voz, velocidad o idioma).
  Future<void> _restartHere() async {
    _clearCache();
    if (!playing) return;
    final wasPlaying = playing;
    _gen++;
    await _stopAll();
    playing = false;
    if (wasPlaying) await play();
  }

  // ------------------------------------------------------------ voces naturales

  String _key() =>
      '${meta?.id}|${Prefs.I.speed}|${narratorVoice?.id}|${dialogueVoiceInfo?.id}|${meta?.useTranslation}';

  void _resetAudio() {
    _clearCache();
    _cur = null;
    _completedFor = -1;
    _resumeAt = 0;
  }

  void _clearCache() {
    for (final f in _cache.values) {
      f.then((p) => _deleteFile(p?.res?.path)).catchError((_) {});
    }
    _cache.clear();
    _cacheKey = _key();
  }

  void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync() && path != _cur?.res?.path) f.deleteSync();
    } catch (_) {}
  }

  void _trimCache() {
    final remove = _cache.keys.where((k) => k < idx - 1 || k > idx + 4).toList();
    for (final k in remove) {
      final f = _cache.remove(k);
      f?.then((p) => _deleteFile(p?.res?.path)).catchError((_) {});
    }
  }

  Future<_Para?> _ensure(int i) {
    final k = _key();
    if (k != _cacheKey) _clearCache();
    return _cache.putIfAbsent(i, () => _makePara(i));
  }

  Future<String> _textForSpeech(int i) async {
    final m = meta, c = content, tr = translation;
    if (m == null || c == null) return '';
    if (m.useTranslation && tr != null && tr[i] == null) {
      final t = await Translator.I.translateOne(c.paras[i]);
      if (t != null) tr[i] = t;
    }
    return textAt(i);
  }

  Future<_Para?> _makePara(int i) async {
    final c = content;
    if (c == null || i < 0 || i >= c.paras.length) return null;
    final text = await _textForSpeech(i);
    final segs = segmentText(text);
    if (segs.isEmpty) return _Para(i, text, const [], null);
    final narr = narratorVoice!;
    final dia = dialogueVoiceInfo;
    final items = <SynthItem>[];
    for (var k = 0; k < segs.length; k++) {
      final s = segs[k];
      final v = (s.dialogue && dia != null) ? dia : narr;
      final last = k == segs.length - 1;
      final switchVoice = !last && segs[k + 1].dialogue != s.dialogue;
      items.add(SynthItem(
        text: s.speak,
        model: Voices.I.modelPath(v),
        tokens: Voices.I.tokensPath(v),
        dataDir: Voices.I.dataDir(v),
        sid: v.sid,
        pauseAfter: last ? 0.55 : (switchVoice ? 0.38 : 0.24),
      ));
    }
    final path = '$_audioDir/p${_fileSeq++}.wav';
    final res = await NeuralTts.I.synth(items, Prefs.I.speed, path);
    return _Para(i, text, segs, res);
  }

  void _prefetch() {
    final c = content;
    if (c == null) return;
    for (var k = idx + 1; k <= idx + 2 && k < c.paras.length; k++) {
      _ensure(k).catchError((_) => null);
    }
    _trimCache();
  }

  Future<void> _playNeural() async {
    final gen = ++_gen;
    loading = true;
    notifyListeners();
    _Para? p;
    try {
      p = await _ensure(idx);
    } catch (e) {
      if (gen != _gen) return;
      loading = false;
      _forceSystem = true;
      notice = 'No pude usar la voz natural en este celular. Sigo con la voz del iPhone.';
      notifyListeners();
      if (playing) await _speakSystem();
      return;
    }
    if (gen != _gen || !playing) return;
    loading = false;
    if (p == null) {
      playing = false;
      notifyListeners();
      return;
    }
    if (p.res == null) {
      _completedFor = -1;
      _advanceNeural();
      return;
    }
    _cur = p;
    _completedFor = -1;
    try {
      await _player.setFilePath(p.res!.path);
    } catch (_) {
      if (gen != _gen) return;
      _advanceNeural();
      return;
    }
    if (gen != _gen || !playing) return;
    unawaited(_player.play());
    notifyListeners();
    _sync();
    _prefetch();
  }

  void _onPosition(Duration pos) {
    final p = _cur;
    if (p == null || p.idx != idx || p.res == null) return;
    final t = pos.inMilliseconds / 1000.0;
    final r = p.res!;
    var k = 0;
    for (var j = 0; j < r.starts.length; j++) {
      if (r.starts[j] <= t + 0.03) k = j;
    }
    if (k < p.spoken.length) {
      final s = p.spoken[k];
      final cur = hl.value;
      if (cur == null || cur.para != idx || cur.start != s.start) hl.value = HL(idx, s.start, s.end);
    }
  }

  void _onNeuralDone() {
    if (!playing || !usingNeural) return;
    final p = _cur;
    if (p == null || p.idx != idx || _completedFor == idx) return;
    _completedFor = idx;
    _advanceNeural();
  }

  void _advanceNeural() {
    final c = content;
    if (c == null) return;
    final next = idx + 1;
    if (next >= c.paras.length) {
      playing = false;
      hl.value = null;
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
      hl.value = null;
      clearSleep();
      _sync();
      return;
    }
    _playNeural();
  }

  /// Escucha cómo suena una voz.
  Future<void> previewVoice(VoiceInfo v) async {
    if (!Voices.I.isReady(v)) return;
    final sample = v.lang == 'en'
        ? 'Hello, I am ${v.name}. This is how I sound reading your book.'
        : 'Hola, soy ${v.name}. —¿Así suena un diálogo? —preguntó ella. Así sueno leyendo tu libro.';
    try {
      final segs = segmentText(sample);
      final items = [
        for (final s in segs)
          SynthItem(
            text: s.speak,
            model: Voices.I.modelPath(v),
            tokens: Voices.I.tokensPath(v),
            dataDir: Voices.I.dataDir(v),
            sid: v.sid,
            pauseAfter: 0.3,
          )
      ];
      final res = await NeuralTts.I.synth(items, Prefs.I.speed, '$_audioDir/preview${_fileSeq++}.wav');
      if (playing) await pause();
      await _preview.setFilePath(res.path);
      unawaited(_preview.play());
    } catch (_) {
      notice = 'No pude reproducir la muestra de ${v.name}.';
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ voz del iPhone

  Future<void> _initSystemVoice() async {
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
      } catch (_) {}
    }
    await _tts.awaitSpeakCompletion(false);
    _tts.setProgressHandler((String text, int start, int end, String w) {
      _lastWordStart = _offset + start;
      hl.value = HL(idx, _offset + start, _offset + end);
    });
    _tts.setCompletionHandler(_onSystemDone);
    _tts.setErrorHandler((dynamic _) {
      if (playing && !usingNeural) _onSystemDone();
    });
    await _applySystemRate();
    await loadSystemVoices();
    final v = currentSystemVoice ?? (sysVoices.isNotEmpty ? sysVoices.first : null);
    if (v != null) {
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    } else {
      await _tts.setLanguage('es-ES');
    }
  }

  Future<void> _applySystemRate() async {
    final s = Prefs.I.speed;
    final double r = Platform.isIOS ? (s >= 1 ? 0.5 + (s - 1) * 0.25 : 0.5 - (1 - s) * 0.4) : s;
    await _tts.setSpeechRate(r.clamp(0.1, Platform.isIOS ? 1.0 : 3.0).toDouble());
  }

  Future<void> loadSystemVoices() async {
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
        return q.contains('premium') ? 0 : (q.contains('enhanced') ? 1 : 2);
      }

      list.sort((a, b) => rank(a).compareTo(rank(b)));
      sysVoices = list;
      notifyListeners();
    } catch (_) {}
  }

  Map<String, String>? get currentSystemVoice {
    for (final v in sysVoices) {
      if (v['name'] == Prefs.I.sysVoiceName && v['locale'] == Prefs.I.sysVoiceLocale) return v;
    }
    return null;
  }

  Future<void> setSystemVoice(Map<String, String> v) async {
    Prefs.I.setSystemVoice(v['name']!, v['locale']!);
    await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    notifyListeners();
    if (playing && !usingNeural) {
      await _restartHere();
    } else if (!playing) {
      await _tts.speak('Hola, así sueno leyendo tu libro.');
    }
  }

  Future<void> _speakSystem() async {
    final c = content;
    if (c == null) return;
    final gen = ++_gen;
    var text = await _textForSpeech(idx);
    if (gen != _gen || !playing) return;
    if (readingEnglish) {
      await _tts.setLanguage('en-US');
    } else {
      final v = currentSystemVoice ?? (sysVoices.isNotEmpty ? sysVoices.first : null);
      if (v != null) await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    }
    final from = _resumeAt.clamp(0, text.length);
    _resumeAt = 0;
    _offset = from;
    _lastWordStart = from;
    text = text.substring(from);
    notifyListeners();
    _sync();
    if (text.trim().isEmpty) {
      _onSystemDone();
      return;
    }
    await _tts.speak(text);
  }

  void _onSystemDone() {
    final c = content;
    if (!playing || c == null || usingNeural) return;
    final next = idx + 1;
    if (next >= c.paras.length) {
      playing = false;
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
      hl.value = null;
      clearSleep();
      _sync();
      return;
    }
    _speakSystem();
  }

  Future<void> _stopAll() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  // ------------------------------------------------------------ ajustes

  Future<void> setSpeed(double s) async {
    Prefs.I.setSpeed(s);
    await _applySystemRate();
    notifyListeners();
    await _restartHere();
  }

  /// Llamar después de cambiar voces en Ajustes.
  Future<void> voicesChanged() async {
    _forceSystem = false;
    notifyListeners();
    await _restartHere();
  }

  void setUseTranslation(bool v) {
    final m = meta;
    if (m == null) return;
    m.useTranslation = v;
    Library.I.touch();
    hl.value = null;
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
