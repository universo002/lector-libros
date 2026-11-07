import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:lector_tts/lector_tts.dart';

import 'library.dart';
import 'models.dart';
import 'prefs.dart';
import 'segmenter.dart';
import 'stats.dart';
import 'translator.dart';

/// Parte del texto que se está leyendo (para resaltarla).
class HL {
  final int para, start, end;
  const HL(this.para, this.start, this.end);
}

class _Utt {
  final int id, para, seg, start, end;
  final bool lastOfPara, lastOfBook;
  const _Utt(this.id, this.para, this.seg, this.start, this.end, this.lastOfPara, this.lastOfBook);
}

const _novelty = {
  'albert', 'bad news', 'bahh', 'bells', 'boing', 'bubbles', 'cellos', 'good news', 'jester', 'organ', 'superstar',
  'trinoids', 'whisper', 'wobble', 'zarvox', 'eddy', 'flo', 'grandma', 'grandpa', 'reed', 'rocko', 'sandy', 'shelley',
  'fred', 'junior', 'ralph', 'kathy',
};

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

/// Junta frases muy cortas seguidas del mismo tipo: la voz suena más fluida.
List<Seg> mergedSegments(String text) {
  final raw = segmentText(text);
  final out = <Seg>[];
  for (final s in raw) {
    if (out.isNotEmpty) {
      final p = out.last;
      if (p.dialogue == s.dialogue && p.speak.length < 70 && p.speak.length + s.speak.length < 230) {
        out[out.length - 1] = Seg(p.start, s.end, s.dialogue, '${p.speak} ${s.speak}');
        continue;
      }
    }
    out.add(s);
  }
  return out;
}

/// Motor de lectura: arma la cola de frases para el motor de voz del iPhone.
class ReaderEngine extends ChangeNotifier {
  ReaderEngine._();
  static final ReaderEngine I = ReaderEngine._();

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

  // Cola nativa
  int _gen = 0;
  int _nextId = 1;
  final Map<int, _Utt> _q = {};
  int _queuedPara = -1;
  bool _enqueueing = false;
  bool _nativePaused = false;
  bool _haltAfterQueue = false;
  bool _interrupted = false;
  int _lastGender = 0;
  Timer? _ticker;

  // Voces
  List<NativeVoice> voices = [];
  NativeVoice? female;
  NativeVoice? male;
  NativeVoice? english;

  // Temporizador
  DateTime? sleepAt;
  bool sleepEndOfSection = false;
  Timer? _sleepTimer;

  // ------------------------------------------------------------ inicio

  Future<void> init() async {
    LectorTts.init();
    LectorTts.onStart = _onStart;
    LectorTts.onFinish = _onFinish;
    LectorTts.onInterrupt = _onInterrupt;
    LectorTts.onRouteLost = _onRouteLost;
    await loadVoices();
  }

  void attachHandler(ReaderAudioHandler h) {
    _handler = h;
    _sync();
  }

  // ------------------------------------------------------------ voces

  Future<void> loadVoices() async {
    voices = await LectorTts.voices();
    final usable = voices.where((v) => !_novelty.contains(_norm(v.name))).toList();
    final es = usable.where((v) => v.lang.toLowerCase().startsWith('es')).toList();
    final en = usable.where((v) => v.lang.toLowerCase().startsWith('en')).toList();
    female = _best(es, const ['monica', 'paulina', 'marisol', 'isabela', 'angelica', 'soledad', 'francisca'], 2);
    male = _best(es, const ['jorge', 'juan', 'diego', 'carlos', 'pablo', 'andres'], 1);
    english = _best(en, const ['ava', 'samantha', 'zoe', 'allison', 'susan', 'evan', 'nathan', 'tom'], 0);
    notifyListeners();
  }

  NativeVoice? _best(List<NativeVoice> list, List<String> names, int gender) {
    int byQuality(NativeVoice a, NativeVoice b) {
      final q = b.quality.compareTo(a.quality);
      if (q != 0) return q;
      // A igual calidad, preferimos español de España (como Mónica y Jorge).
      final ea = a.lang.toLowerCase() == 'es-es' ? 0 : 1;
      final eb = b.lang.toLowerCase() == 'es-es' ? 0 : 1;
      return ea.compareTo(eb);
    }

    for (final n in names) {
      final c = list.where((v) => _norm(v.name).startsWith(n)).toList()..sort(byQuality);
      if (c.isNotEmpty) return c.first;
    }
    if (gender != 0) {
      final c = list.where((v) => v.gender == gender).toList()..sort(byQuality);
      if (c.isNotEmpty) return c.first;
    }
    final c = List<NativeVoice>.of(list)..sort(byQuality);
    return c.isEmpty ? null : c.first;
  }

  NativeVoice? get narrator => Prefs.I.narratorMale ? (male ?? female) : (female ?? male);
  NativeVoice? get otherVoice => Prefs.I.narratorMale ? female : male;

  String get currentVoiceLabel {
    final n = narrator;
    if (n == null) return 'Voz del iPhone';
    return n.quality >= 2 ? '${n.name} · ${n.qualityLabel}' : n.name;
  }

  // ------------------------------------------------------------ libro

  Future<void> open(BookMeta m) async {
    if (meta?.id == m.id && content != null) {
      m.opened = DateTime.now();
      Library.I.touch();
      return;
    }
    if (playing) await pause();
    await _hardStop();
    final c = await Library.I.content(m.id);
    final tr = await Library.I.translation(m.id);
    meta = m;
    content = c;
    translation = tr;
    idx = c.paras.isEmpty ? 0 : m.position.clamp(0, c.paras.length - 1);
    _seg = 0;
    _lastGender = 0;
    hl.value = null;
    m.opened = DateTime.now();
    Library.I.touch();
    notifyListeners();
    _sync();
  }

  void close() {
    playing = false;
    _hardStop();
    _stopTicker();
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
    _interrupted = false;
    _startTicker();
    notifyListeners();
    if (_nativePaused && _q.isNotEmpty) {
      _nativePaused = false;
      final ok = await LectorTts.resume();
      if (ok) {
        _sync();
        return;
      }
    }
    await _startFrom();
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _stopTicker();
    await LectorTts.pause();
    _nativePaused = true;
    loading = false;
    notifyListeners();
    _sync();
    _save();
    Stats.I.save();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> jumpTo(int i, {bool? play, int seg = 0}) async {
    final c = content;
    if (c == null || c.paras.isEmpty) return;
    final shouldPlay = play ?? playing;
    await _hardStop();
    idx = i.clamp(0, c.paras.length - 1);
    _seg = seg;
    hl.value = null;
    _save();
    notifyListeners();
    _sync();
    if (shouldPlay) {
      playing = false;
      await this.play();
    } else {
      playing = false;
      _stopTicker();
      notifyListeners();
    }
  }

  Future<void> next() => jumpTo(idx + 1);
  Future<void> prev() => jumpTo(idx - 1);

  /// Vuelve a escuchar la frase actual.
  Future<void> repeatSentence() => jumpTo(idx, seg: _seg, play: true);

  Future<void> prevSentence() async {
    if (_seg > 0) return jumpTo(idx, seg: _seg - 1);
    if (idx == 0) return jumpTo(0);
    final n = mergedSegments(textAt(idx - 1)).length;
    return jumpTo(idx - 1, seg: n > 0 ? n - 1 : 0);
  }

  Future<void> nextSentence() async {
    final n = mergedSegments(textAt(idx)).length;
    if (_seg + 1 < n) return jumpTo(idx, seg: _seg + 1);
    return jumpTo(idx + 1);
  }

  Future<void> skipSection(int dir) async {
    final c = content;
    if (c == null) return;
    final s = c.sectionOf(idx);
    if (dir < 0 && idx > c.sections[s].start + 2) return jumpTo(c.sections[s].start);
    final t = (s + dir).clamp(0, c.sections.length - 1);
    return jumpTo(c.sections[t].start);
  }

  /// Después de cambiar voz, velocidad o idioma: sigue desde la frase actual con lo nuevo.
  Future<void> _restartHere() async {
    if (playing) {
      await _startFrom();
    } else {
      await _hardStop();
    }
  }

  Future<void> _hardStop() async {
    _gen++;
    _q.clear();
    _nativePaused = false;
    _enqueueing = false;
    _haltAfterQueue = false;
    await LectorTts.stop();
  }

  // ------------------------------------------------------------ cola de frases

  Future<void> _startFrom() async {
    await _hardStop();
    final gen = _gen;
    _queuedPara = idx - 1;
    await _enqueuePara(idx, gen, fromSeg: _seg);
    if (gen != _gen) return;
    await _enqueuePara(_queuedPara + 1, gen);
  }

  Future<String> _textForSpeech(int i, {bool show = false}) async {
    final m = meta, c = content, tr = translation;
    if (m == null || c == null) return '';
    if (m.useTranslation && tr != null && tr[i] == null) {
      if (show) {
        loading = true;
        notifyListeners();
      }
      final t = await Translator.I.translateOne(c.paras[i]);
      if (t != null) tr[i] = t;
      if (show) {
        loading = false;
        notifyListeners();
      }
    }
    return textAt(i);
  }

  Future<void> _enqueuePara(int p, int gen, {int fromSeg = 0}) async {
    final c = content;
    if (c == null || p < 0 || p >= c.paras.length) return;
    // Temporizador «al terminar el capítulo»: no seguimos con el capítulo siguiente.
    if (sleepEndOfSection && p != idx && c.sections.any((s) => s.start == p && s.start != 0)) {
      _haltAfterQueue = true;
      return;
    }
    _enqueueing = true;
    var guard = 0;
    var para = p;
    while (gen == _gen && para < c.paras.length && guard < 20) {
      guard++;
      final text = await _textForSpeech(para, show: para == idx);
      if (gen != _gen) return;
      final segs = mergedSegments(text);
      final start = para == p ? fromSeg.clamp(0, segs.isEmpty ? 0 : segs.length - 1) : 0;
      final utts = _build(para, segs, start, c);
      _queuedPara = para;
      if (utts.isEmpty) {
        para++; // párrafo sin texto para leer: seguimos con el próximo
        continue;
      }
      try {
        await LectorTts.enqueue(utts);
      } catch (_) {
        notice = 'No pude usar la voz del iPhone.';
        playing = false;
        notifyListeners();
      }
      break;
    }
    _enqueueing = false;
  }

  double _rate(double s) {
    // 0.5 es la velocidad «normal» de Apple, rápida para leer libros. Acá 1.0× = 0.46.
    final r = s <= 1 ? 0.46 - (1 - s) * 0.32 : 0.46 + (s - 1) * 0.26;
    return r.clamp(0.2, 0.78).toDouble();
  }

  double _voiceFactor(NativeVoice? v) {
    if (v != null && male != null && v.id == male!.id) return Prefs.I.speedMale;
    return Prefs.I.speedFemale;
  }

  /// Arma las frases con su voz, tono, velocidad y pausas.
  List<Utterance> _build(int para, List<Seg> segs, int from, BookContent c, {bool register = true}) {
    final pr = Prefs.I;
    final narr = narrator;
    final other = otherVoice;
    final english = readingEnglish;
    final cue = paragraphCue(segs);
    final heading = c.sections.any((s) => s.start == para && s.title != 'Inicio');
    final nextHeading = c.sections.any((s) => s.start == para + 1);
    final pauseK = const [0.55, 1.0, 1.7][pr.pauseLevel] / pr.speed.clamp(0.6, 1.8);

    // ¿Quién habla en este párrafo? Si no hay pistas, alternamos (en una charla suelen turnarse).
    var gender = cue.gender;
    if (segs.any((s) => s.dialogue)) {
      if (gender == 0) {
        gender = _lastGender == 0 ? (pr.narratorMale ? 2 : 1) : (_lastGender == 1 ? 2 : 1);
      }
      if (register) _lastGender = gender;
    }

    final out = <Utterance>[];
    for (var k = from; k < segs.length; k++) {
      final s = segs[k];
      NativeVoice? voice = narr;
      var pitch = 1.0;
      var volume = 1.0;
      var spd = pr.speed;
      var lang = 'es-ES';

      if (english) {
        voice = this.english;
        lang = 'en-US';
      } else if (s.dialogue) {
        switch (pr.dialogueMode) {
          case DialogueMode.igual:
            break;
          case DialogueMode.tono:
            pitch = 1.12;
            spd *= 0.96;
            break;
          case DialogueMode.otraVoz:
            if (other != null) {
              voice = other;
            } else {
              pitch = 1.12;
            }
            break;
          case DialogueMode.personajes:
            final target = gender == 1 ? male : female;
            voice = target ?? narr;
            // Si el personaje tiene la misma voz que el narrador, le cambiamos un poco el tono.
            if (voice?.id == narr?.id) pitch = gender == 1 ? 0.94 : 1.1;
            break;
        }
        if (pr.expressive) {
          if (cue.tone == 1) {
            volume = 0.72;
            spd *= 0.9;
            pitch -= 0.04;
          } else if (cue.tone == 2 || s.speak.endsWith('!')) {
            pitch += 0.06;
            spd *= 1.03;
          }
        }
      }
      if (!english) spd *= _voiceFactor(voice);

      final last = k == segs.length - 1;
      double post;
      if (last) {
        post = (heading || nextHeading) ? 0.95 : 0.5;
      } else {
        post = segs[k + 1].dialogue != s.dialogue ? 0.34 : 0.13;
      }
      final pre = (heading && k == 0) ? 0.25 : 0.0;

      final text = speechText(s.speak, spanish: !english);
      if (text.isEmpty) continue;
      final id = _nextId++;
      if (register) {
        final lastOfBook = last && para == c.paras.length - 1;
        _q[id] = _Utt(id, para, k, s.start, s.end, last, lastOfBook);
      }
      out.add(Utterance(
        id: id,
        text: text,
        voiceId: voice?.id,
        lang: lang,
        rate: _rate(spd),
        pitch: pitch.clamp(0.75, 1.5).toDouble(),
        volume: volume,
        pre: pre,
        post: post * pauseK,
      ));
    }
    return out;
  }

  void _onStart(int id) {
    final u = _q[id];
    if (u == null) return;
    if (u.para != idx) {
      idx = u.para;
      _save();
      notifyListeners();
    }
    _seg = u.seg;
    hl.value = HL(u.para, u.start, u.end);
    _sync();
    // Cuando empieza el último párrafo de la cola, preparamos el siguiente: así no hay cortes.
    if (u.para >= _queuedPara && !_enqueueing && !_haltAfterQueue) {
      _enqueuePara(_queuedPara + 1, _gen);
    }
  }

  void _onFinish(int id) {
    final u = _q.remove(id);
    if (u == null) return;
    if (u.lastOfBook) {
      playing = false;
      _stopTicker();
      hl.value = null;
      final m = meta;
      if (m != null) {
        m.position = u.para;
        Library.I.touch();
      }
      Stats.I.bookFinished();
      notifyListeners();
      _sync();
      return;
    }
    if (u.lastOfPara) {
      final c = content;
      if (c != null && u.para + 1 < c.paras.length && _q.isNotEmpty) {
        // El próximo párrafo ya está en cola; actualizamos la posición.
        final timeUp = sleepAt != null && DateTime.now().isAfter(sleepAt!);
        if (timeUp) {
          idx = u.para + 1;
          _seg = 0;
          clearSleep();
          pause();
          return;
        }
      }
    }
    if (_q.isEmpty && playing && !_enqueueing) {
      if (_haltAfterQueue) {
        // Terminó el capítulo con el temporizador activo.
        _haltAfterQueue = false;
        final c = content;
        if (c != null && u.para + 1 < c.paras.length) idx = u.para + 1;
        _seg = 0;
        playing = false;
        _stopTicker();
        clearSleep();
        _save();
        hl.value = null;
        notifyListeners();
        _sync();
      } else {
        // La cola se vació (por ejemplo, la traducción tardó): seguimos.
        _seg = 0;
        final c = content;
        if (c != null && u.para + 1 < c.paras.length) {
          idx = u.para + 1;
          _startFrom();
        }
      }
    }
  }

  void _onInterrupt(bool began, bool resume) {
    if (began) {
      if (playing) {
        _interrupted = true;
        pause();
      }
    } else if (resume && _interrupted) {
      _interrupted = false;
      play();
    }
  }

  void _onRouteLost() {
    if (!playing) return;
    playing = false;
    _nativePaused = true;
    _stopTicker();
    notice = 'Se desconectaron los auriculares: pausé la lectura.';
    notifyListeners();
    _sync();
    _save();
  }

  // ------------------------------------------------------------ muestras

  Future<void> _sampleStop() async {
    if (playing) await pause();
    await _hardStop();
  }

  Future<void> preview(NativeVoice v) async {
    await _sampleStop();
    final english = v.lang.toLowerCase().startsWith('en');
    await LectorTts.enqueue([
      Utterance(
        id: -1,
        text: english
            ? 'Hello. This is how I sound reading your book.'
            : 'Hola, soy ${v.name}. Así sueno cuando leo tu libro, frase por frase.',
        voiceId: v.id,
        lang: v.lang,
        rate: _rate(Prefs.I.speed * _voiceFactor(v)),
      ),
    ]);
  }

  /// Un ejemplo corto de narración con diálogos, con los ajustes actuales.
  Future<void> previewDialogue() async {
    await _sampleStop();
    const sample = 'Ella se acercó a la ventana y miró la lluvia.\n'
        '—¿De verdad creés que vamos a llegar a tiempo? —preguntó ella en voz baja.';
    const sample2 = '—Si salimos ahora, sí —respondió él—. ¡Vamos!';
    final fake = BookContent(const [Section('Inicio', 0)], const [sample, sample2]);
    final saveGender = _lastGender;
    _lastGender = 0;
    final u1 = _build(0, mergedSegments(sample), 0, fake, register: false);
    final u2 = _build(1, mergedSegments(sample2), 0, fake, register: false);
    _lastGender = saveGender;
    await LectorTts.enqueue([...u1, ...u2]);
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
    if (playing) _restartHere();
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

  // ------------------------------------------------------------ marcadores y notas

  void toggleBookmark(int i) {
    final m = meta;
    if (m == null) return;
    if (m.bookmarks.contains(i)) {
      m.bookmarks.remove(i);
      m.notes.remove('$i');
    } else {
      m.bookmarks.add(i);
      m.bookmarks.sort();
    }
    Library.I.touch();
    notifyListeners();
  }

  void setNote(int i, String text) {
    final m = meta;
    if (m == null) return;
    final t = text.trim();
    if (t.isEmpty) {
      m.notes.remove('$i');
    } else {
      m.notes['$i'] = t;
      if (!m.bookmarks.contains(i)) {
        m.bookmarks.add(i);
        m.bookmarks.sort();
      }
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

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (playing) Stats.I.addSeconds(5);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

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
/// Los botones de adelantar y atrasar saltan de a una frase.
class ReaderAudioHandler extends BaseAudioHandler {
  String _lastKey = '';

  @override
  Future<void> play() => ReaderEngine.I.play();

  @override
  Future<void> pause() => ReaderEngine.I.pause();

  @override
  Future<void> stop() => ReaderEngine.I.pause();

  @override
  Future<void> skipToNext() => ReaderEngine.I.nextSentence();

  @override
  Future<void> skipToPrevious() => ReaderEngine.I.prevSentence();

  @override
  Future<void> fastForward() => ReaderEngine.I.nextSentence();

  @override
  Future<void> rewind() => ReaderEngine.I.prevSentence();

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
