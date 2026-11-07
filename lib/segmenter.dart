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
