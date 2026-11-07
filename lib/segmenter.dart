/// Divide un párrafo en frases y marca cuáles son diálogo y cuáles narración.
///
/// Reglas:
/// - Párrafo que empieza con raya (— – ―): lo de después de la raya es diálogo,
///   y cada raya siguiente alterna entre narración («—dijo ella—») y diálogo.
/// - Texto entre comillas (“ ” « » ") es diálogo.
class Seg {
  final int start, end; // posiciones en el texto que se muestra
  final bool dialogue;
  final String speak; // texto limpio que se manda a la voz
  const Seg(this.start, this.end, this.dialogue, this.speak);
}

class _Piece {
  final int start, end;
  final bool dialogue;
  const _Piece(this.start, this.end, this.dialogue);
}

const _dashes = {'—', '–', '―'};
final _letter = RegExp(r'[0-9A-Za-zÀ-ÿ]');
final _sentenceEnd = RegExp(r'[.!?…]+["»”’)\]]*\s+');
final _cleanChars = RegExp('[—–―“”«»"]');
final _spaces = RegExp(r'\s+');
final _leadingPunct = RegExp(r'^[\s.,;:]+');

List<_Piece> _pieces(String t) {
  final out = <_Piece>[];
  var i = 0;
  while (i < t.length && t[i] == ' ') {
    i++;
  }
  final startsDash = i < t.length &&
      (_dashes.contains(t[i]) || (t[i] == '-' && i + 1 < t.length && t[i + 1] != ' ' && t[i + 1] != '-'));
  if (startsDash) {
    var dialogue = true;
    var s = i + 1;
    for (var k = i + 1; k < t.length; k++) {
      if (_dashes.contains(t[k])) {
        out.add(_Piece(s, k, dialogue));
        dialogue = !dialogue;
        s = k + 1;
      }
    }
    out.add(_Piece(s, t.length, dialogue));
    return out;
  }

  var inQuote = false;
  var s = 0;
  for (var k = 0; k < t.length; k++) {
    final c = t[k];
    final open = c == '“' || c == '«' || (c == '"' && !inQuote);
    final close = c == '”' || c == '»' || (c == '"' && inQuote);
    if (!inQuote && open) {
      out.add(_Piece(s, k, false));
      s = k;
      inQuote = true;
    } else if (inQuote && close) {
      out.add(_Piece(s, k + 1, true));
      s = k + 1;
      inQuote = false;
    }
  }
  out.add(_Piece(s, t.length, inQuote));
  return out;
}

String cleanForSpeech(String s) =>
    s.replaceAll(_cleanChars, ' ').replaceAll(_spaces, ' ').replaceFirst(_leadingPunct, '').trim();

void _add(List<Seg> out, String t, int a, int b, bool d) {
  while (a < b && (t[a] == ' ' || t[a] == '\n')) {
    a++;
  }
  while (b > a && (t[b - 1] == ' ' || t[b - 1] == '\n')) {
    b--;
  }
  if (b <= a) return;
  final speak = cleanForSpeech(t.substring(a, b));
  if (!_letter.hasMatch(speak)) return;
  // Frases muy largas: se cortan en comas o punto y coma para que la voz respire.
  if (speak.length > 380) {
    final sub = t.substring(a, b);
    var cut = sub.lastIndexOf(RegExp(r'[,;:]\s'), 300);
    if (cut > 80) {
      _add(out, t, a, a + cut + 1, d);
      _add(out, t, a + cut + 1, b, d);
      return;
    }
  }
  out.add(Seg(a, b, d, speak));
}

final _abbrevEnd = RegExp(
  r'\b(Sr|Sra|Srta|Sres|Dr|Dra|Ud|Uds|Vd|Vds|etc|pág|págs|núm|aprox|Lic|Ing|Prof|Mr|Mrs|Ms|St|vs|Jr|cap|vol)\.$',
  caseSensitive: false,
);
final _startsLower = RegExp(r'^[a-záéíóúüñ]');

List<Seg> segmentText(String t) {
  final raw = <Seg>[];
  for (final p in _pieces(t)) {
    if (p.end <= p.start) continue;
    final sub = t.substring(p.start, p.end);
    var s = p.start;
    for (final m in _sentenceEnd.allMatches(sub)) {
      _add(raw, t, s, p.start + m.end, p.dialogue);
      s = p.start + m.end;
    }
    _add(raw, t, s, p.end, p.dialogue);
  }
  // Une frases que se cortaron mal (después de «Sr.», «etc.» o «…» seguido de minúscula).
  final segs = <Seg>[];
  for (final g in raw) {
    if (segs.isNotEmpty) {
      final prev = segs.last;
      final glue = prev.dialogue == g.dialogue &&
          (_abbrevEnd.hasMatch(prev.speak) || _startsLower.hasMatch(g.speak)) &&
          prev.speak.length + g.speak.length < 420;
      if (glue) {
        segs[segs.length - 1] = Seg(prev.start, g.end, g.dialogue, '${prev.speak} ${g.speak}');
        continue;
      }
    }
    segs.add(g);
  }
  return segs;
}

// ------------------------------------------------------------ texto para la voz

const _abbrevEs = {
  'Sr.': 'señor',
  'Sra.': 'señora',
  'Srta.': 'señorita',
  'Sres.': 'señores',
  'Dr.': 'doctor',
  'Dra.': 'doctora',
  'Ud.': 'usted',
  'Uds.': 'ustedes',
  'Vd.': 'usted',
  'etc.': 'etcétera',
  'pág.': 'página',
  'págs.': 'páginas',
  'núm.': 'número',
  'aprox.': 'aproximadamente',
  'Lic.': 'licenciado',
  'Ing.': 'ingeniero',
  'Prof.': 'profesor',
  'Mr.': 'míster',
  'Mrs.': 'misis',
};

final _footnote = RegExp(r'(?<=[A-Za-zÁÉÍÓÚáéíóúñÑ;:!?»”])\d{1,3}(?=[\s.,;:]|$)');
final _symbols = RegExp(r'[*_#~^|<>\[\]{}•·§¶]');
final _allCaps = RegExp(r'\b[A-ZÁÉÍÓÚÑÜ]{4,}\b');
final _dots = RegExp(r'\.{3,}');
final _romanHeading = RegExp(r'\b(cap[ií]tulo|parte|libro|chapter|part|book)\s+([IVXLC]{1,7})\b', caseSensitive: false);
final _endPunct = RegExp(r'[.!?…:;]["»”’)]*$');

int _roman(String r) {
  const v = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100};
  var total = 0;
  for (var i = 0; i < r.length; i++) {
    final a = v[r[i].toUpperCase()] ?? 0;
    final b = i + 1 < r.length ? (v[r[i + 1].toUpperCase()] ?? 0) : 0;
    total += a < b ? -a : a;
  }
  return total;
}

/// Prepara una frase para que la voz la lea clara.
String speechText(String s, {bool spanish = true}) {
  var t = s;
  t = t.replaceAllMapped(_romanHeading, (m) => '${m[1]} ${_roman(m[2]!)}');
  if (spanish) {
    _abbrevEs.forEach((k, v) {
      t = t.replaceAll(RegExp('(?<![A-Za-zÁÉÍÓÚáéíóúñ])${RegExp.escape(k)}'), v);
    });
  }
  t = t.replaceAll(_footnote, '');
  t = t.replaceAll(_symbols, ' ');
  t = t.replaceAll(_dots, '…');
  t = t.replaceAllMapped(_allCaps, (m) {
    final w = m[0]!;
    return w[0] + w.substring(1).toLowerCase();
  });
  t = t.replaceAll(_spaces, ' ').trim();
  // Que cada frase cierre con puntuación: la voz baja el tono y hace la pausa.
  if (t.isNotEmpty && !_endPunct.hasMatch(t)) t = '$t.';
  return t;
}

// ------------------------------------------------------------ quién habla y cómo

/// Pista sobre el diálogo de un párrafo: quién habla (0 no se sabe, 1 hombre, 2 mujer)
/// y en qué tono (0 normal, 1 susurro, 2 grito).
class Cue {
  final int gender;
  final int tone;
  const Cue(this.gender, this.tone);
}

const _verbsEs =
    'dijo|respondió|preguntó|contestó|exclamó|susurró|gritó|murmuró|añadió|replicó|insistió|agregó|explicó|comentó|'
    'suspiró|repitió|interrumpió|admitió|confesó|afirmó|protestó|ordenó|pidió|bromeó|musitó|balbuceó|declaró|anunció|'
    'advirtió|aseguró|continuó|prosiguió|concluyó|sollozó|chilló|bramó|rugió|masculló|terció|inquirió|rió|sonrió|'
    'opinó|propuso|sugirió|corrigió|negó|aclaró|reconoció|observó|apuntó|señaló|gruñó|jadeó|tartamudeó';
const _verbsEn =
    'said|asked|replied|answered|whispered|shouted|yelled|cried|muttered|added|called|snapped|murmured|exclaimed|'
    'continued|sighed|laughed|told|demanded|insisted|growled|hissed|screamed|admitted|explained|agreed|offered';

final _afterEs = RegExp('(?:$_verbsEs)\\s+(él|ella|el\\s+[a-záéíóúñ]+|la\\s+[a-záéíóúñ]+|un\\s+[a-záéíóúñ]+|una\\s+[a-záéíóúñ]+|[A-ZÁÉÍÓÚÑ][a-záéíóúñ]+)');
final _beforeEs = RegExp('(?:^|\\s)(él|ella|Él|Ella)\\s+(?:$_verbsEs)');
final _afterEn = RegExp('(?:$_verbsEn)\\s+(she|he|the\\s+[a-z]+|[A-Z][a-z]+)');
final _beforeEn = RegExp('(?:^|\\s)(she|he|She|He)\\s+(?:$_verbsEn)');

final _whisper = RegExp(r'susurr|murmur|musit|mascull|en voz baja|whisper|murmur|mutter|under (her|his) breath', caseSensitive: false);
final _shout = RegExp(r'grit|exclam|chill|bram|rugi|vocifer|aull|shout|yell|scream|exclaim|roar', caseSensitive: false);

const _femaleWords = {
  'mujer', 'chica', 'niña', 'señora', 'señorita', 'madre', 'mamá', 'abuela', 'hermana', 'hija', 'reina', 'princesa',
  'anciana', 'joven', 'muchacha', 'esposa', 'tía', 'doctora', 'maestra', 'profesora', 'amiga', 'dama', 'bruja',
  'woman', 'girl', 'lady', 'mother', 'queen', 'princess', 'sister', 'daughter', 'wife', 'aunt', 'witch', 'old woman',
};
const _maleWords = {
  'hombre', 'chico', 'niño', 'señor', 'padre', 'papá', 'abuelo', 'hermano', 'hijo', 'rey', 'príncipe', 'anciano',
  'muchacho', 'esposo', 'marido', 'tío', 'doctor', 'maestro', 'profesor', 'amigo', 'caballero', 'mago', 'capitán',
  'man', 'boy', 'gentleman', 'father', 'king', 'prince', 'brother', 'son', 'husband', 'uncle', 'wizard', 'captain',
};

int _genderOf(String who) {
  final w = who.trim();
  final lw = w.toLowerCase();
  if (lw == 'ella' || lw == 'she') return 2;
  if (lw == 'él' || lw == 'he') return 1;
  final parts = lw.split(RegExp(r'\s+'));
  if (parts.length == 2) {
    final art = parts[0], noun = parts[1];
    if (art == 'la' || art == 'una') return 2;
    if (art == 'el' || art == 'un') {
      // «el joven», «el doctor»: usamos el sustantivo si lo conocemos.
      if (_femaleWords.contains(noun)) return 2;
      return 1;
    }
    if (art == 'the') {
      if (_femaleWords.contains(noun)) return 2;
      if (_maleWords.contains(noun)) return 1;
      return 0;
    }
  }
  // Un nombre propio: en español, los que terminan en «a» suelen ser de mujer y en «o» de hombre.
  if (w.isNotEmpty && w[0].toUpperCase() == w[0] && w[0].toLowerCase() != w[0]) {
    if (lw.endsWith('a')) return 2;
    if (lw.endsWith('o') || lw.endsWith('os')) return 1;
  }
  return 0;
}

/// Busca en la narración del párrafo quién habla y cómo (por ejemplo «—dijo ella en voz baja»).
Cue paragraphCue(List<Seg> segs) {
  if (!segs.any((s) => s.dialogue)) return const Cue(0, 0);
  final narr = segs.where((s) => !s.dialogue).map((s) => s.speak).join(' ');
  var gender = 0;
  for (final rx in [_afterEs, _beforeEs, _afterEn, _beforeEn]) {
    final m = rx.firstMatch(narr);
    if (m != null) {
      gender = _genderOf(m.group(1)!);
      if (gender != 0) break;
    }
  }
  var tone = 0;
  if (_whisper.hasMatch(narr)) {
    tone = 1;
  } else if (_shout.hasMatch(narr)) {
    tone = 2;
  }
  return Cue(gender, tone);
}
