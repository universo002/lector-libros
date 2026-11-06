import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

/// Abre un PDF, EPUB o TXT en un hilo aparte (así la app no se traba con
/// libros de 1000+ páginas) y devuelve título, secciones y párrafos.
Future<Map<String, dynamic>> importBook(String path, void Function(double progress, String label) onProgress) async {
  final rp = ReceivePort();
  final done = Completer<Map<String, dynamic>>();
  final iso = await Isolate.spawn(_entry, [rp.sendPort, path], onError: rp.sendPort, onExit: rp.sendPort);
  rp.listen((msg) {
    if (done.isCompleted) return;
    if (msg is Map && msg['p'] != null) {
      onProgress((msg['p'] as num).toDouble(), msg['l'] as String);
    } else if (msg is Map && msg['ok'] != null) {
      done.complete(Map<String, dynamic>.from(msg['ok'] as Map));
    } else if (msg is Map && msg['err'] != null) {
      done.completeError(ImportError(msg['err'] as String));
    } else if (msg is List) {
      done.completeError(ImportError(msg.isEmpty ? 'error' : msg.first.toString()));
    } else if (msg == null) {
      done.completeError(ImportError('El proceso se cerró antes de terminar.'));
    }
  });
  try {
    return await done.future;
  } finally {
    rp.close();
    iso.kill();
  }
}

class ImportError implements Exception {
  final String message;
  ImportError(this.message);
  bool get isEmpty => message == 'empty';
  @override
  String toString() => message;
}

void _entry(List<dynamic> args) {
  final sp = args[0] as SendPort;
  final path = args[1] as String;
  try {
    final ext = path.split('.').last.toLowerCase();
    final fname = path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
    final Map<String, dynamic> r;
    if (ext == 'pdf') {
      r = _pdf(path, fname, sp);
    } else if (ext == 'epub') {
      r = _epub(path, fname, sp);
    } else {
      r = _txt(path, fname, sp);
    }
    final paras = r['paras'] as List<String>;
    if (paras.isEmpty) {
      sp.send({'err': 'empty'});
      return;
    }
    r['lang'] = detectLang(paras);
    sp.send({'ok': r});
  } catch (e) {
    sp.send({'err': e.toString()});
  }
}

// ---------------------------------------------------------------- PDF

Map<String, dynamic> _pdf(String path, String fname, SendPort sp) {
  final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
  final n = doc.pages.count;
  final extractor = PdfTextExtractor(doc);
  final paras = <String>[];
  final pageStart = <int>[];
  for (var i = 0; i < n; i++) {
    pageStart.add(paras.length);
    var t = '';
    try {
      t = extractor.extractText(startPageIndex: i, endPageIndex: i);
    } catch (_) {}
    paras.addAll(reflow(t));
    if (i % 5 == 0 || i == n - 1) sp.send({'p': (i + 1) / n, 'l': 'Página ${i + 1} de $n'});
  }

  // Índice del PDF (marcadores), si tiene.
  var sections = <Map<String, dynamic>>[];
  try {
    final bm = doc.bookmarks;
    for (var k = 0; k < bm.count; k++) {
      final b = bm[k];
      final dest = b.destination;
      if (dest == null) continue;
      final pi = doc.pages.indexOf(dest.page);
      if (pi >= 0 && pi < pageStart.length && b.title.trim().isNotEmpty) {
        sections.add({'t': b.title.trim(), 's': pageStart[pi]});
      }
    }
  } catch (_) {}
  sections = _clean(sections, paras.length);
  if (sections.length < 2) sections = _detectHeadings(paras);
  if (sections.length < 2) {
    sections = [];
    for (var p = 0; p < n; p += 10) {
      final end = (p + 10).clamp(0, n);
      sections.add({'t': 'Páginas ${p + 1}–$end', 's': pageStart[p]});
    }
    sections = _clean(sections, paras.length);
  }

  var title = fname, author = '';
  try {
    final info = doc.documentInformation;
    if (info.title.trim().length > 2) title = info.title.trim();
    author = info.author.trim();
  } catch (_) {}
  doc.dispose();
  return {'title': title, 'author': author, 'format': 'PDF', 'pages': n, 'sections': sections, 'paras': paras};
}

// ---------------------------------------------------------------- TXT

Map<String, dynamic> _txt(String path, String fname, SendPort sp) {
  sp.send({'p': 0.3, 'l': 'Leyendo el texto…'});
  final bytes = File(path).readAsBytesSync();
  String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    text = latin1.decode(bytes);
  }
  final paras = reflow(text);
  var sections = _detectHeadings(paras);
  if (sections.length < 2) {
    sections = [
      for (var i = 0; i < paras.length; i += 120) {'t': 'Parte ${i ~/ 120 + 1}', 's': i}
    ];
  }
  return {
    'title': fname,
    'author': '',
    'format': 'TXT',
    'pages': (text.length / 1800).ceil(),
    'sections': _clean(sections, paras.length),
    'paras': paras,
  };
}

// ---------------------------------------------------------------- EPUB

Iterable<XmlElement> _els(XmlNode d, String local) =>
    d.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

T? _first<T>(Iterable<T> it) => it.isEmpty ? null : it.first;

String _dir(String p) => p.contains('/') ? p.substring(0, p.lastIndexOf('/') + 1) : '';

String _resolve(String base, String href) {
  var h = href;
  try {
    h = Uri.decodeFull(href);
  } catch (_) {}
  final parts = <String>[];
  for (final s in (base + h).split('/')) {
    if (s == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (s.isNotEmpty && s != '.') {
      parts.add(s);
    }
  }
  return parts.join('/');
}

Map<String, dynamic> _epub(String path, String fname, SendPort sp) {
  final arc = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final files = <String, ArchiveFile>{};
  for (final f in arc.files) {
    if (f.isFile) files[f.name] = f;
  }
  String read(String name) {
    final f = files[name];
    if (f == null) return '';
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final container = XmlDocument.parse(read('META-INF/container.xml'));
  final opfPath = _first(_els(container, 'rootfile'))?.getAttribute('full-path');
  if (opfPath == null) throw ImportError('EPUB sin índice');
  final base = _dir(opfPath);
  final opf = XmlDocument.parse(read(opfPath));

  var title = _first(_els(opf, 'title'))?.innerText.trim() ?? '';
  if (title.isEmpty) title = fname;
  final author = _first(_els(opf, 'creator'))?.innerText.trim() ?? '';

  final manifest = <String, String>{};
  String? navHref, ncxHref;
  for (final it in _els(opf, 'item')) {
    final id = it.getAttribute('id'), href = it.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = href;
    if ((it.getAttribute('properties') ?? '').split(' ').contains('nav')) navHref = href;
    if (it.getAttribute('media-type') == 'application/x-dtbncx+xml') ncxHref = href;
  }

  // Títulos de capítulos desde la tabla de contenidos.
  final toc = <String, String>{};
  if (ncxHref != null) {
    final ncxPath = _resolve(base, ncxHref);
    try {
      final ncx = XmlDocument.parse(read(ncxPath));
      for (final np in _els(ncx, 'navPoint')) {
        final label = _first(_els(np, 'text'))?.innerText.trim();
        final src = _first(_els(np, 'content'))?.getAttribute('src');
        if (label != null && label.isNotEmpty && src != null) {
          toc.putIfAbsent(_resolve(_dir(ncxPath), src.split('#').first), () => label);
        }
      }
    } catch (_) {}
  }
  if (toc.isEmpty && navHref != null) {
    final navPath = _resolve(base, navHref);
    try {
      final nav = html_parser.parse(read(navPath));
      for (final a in nav.querySelectorAll('nav a')) {
        final href = a.attributes['href'];
        final label = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (href != null && label.isNotEmpty) {
          toc.putIfAbsent(_resolve(_dir(navPath), href.split('#').first), () => label);
        }
      }
    } catch (_) {}
  }

  final spine = _els(opf, 'itemref').map((e) => e.getAttribute('idref')).whereType<String>().toList();
  final paras = <String>[];
  final sections = <Map<String, dynamic>>[];
  for (var n = 0; n < spine.length; n++) {
    final href = manifest[spine[n]];
    if (href == null) continue;
    final p = _resolve(base, href);
    final raw = read(p);
    if (raw.isEmpty) continue;
    sp.send({'p': (n + 1) / spine.length, 'l': 'Capítulo ${n + 1} de ${spine.length}'});
    final body = html_parser.parse(raw).body;
    if (body == null) continue;
    final blocks = <String>[];
    String? heading;
    _walk(body, blocks, (h) => heading ??= h);
    if (blocks.isEmpty) continue;
    var t = toc[p] ?? heading ?? 'Sección ${sections.length + 1}';
    if (t.length > 80) t = '${t.substring(0, 80)}…';
    sections.add({'t': t, 's': paras.length});
    for (final b in blocks) {
      paras.addAll(splitLong(b));
    }
  }
  final pages = (paras.fold<int>(0, (a, s) => a + s.length) / 1800).ceil();
  return {
    'title': title,
    'author': author,
    'format': 'EPUB',
    'pages': pages,
    'sections': _clean(sections, paras.length),
    'paras': paras,
  };
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'div', 'section', 'article', 'td', 'dd', 'dt',
  'pre', 'figcaption', 'header', 'footer', 'aside', 'ul', 'ol', 'table', 'tr', 'tbody', 'main', 'figure'
};
const _skipTags = {'script', 'style', 'head', 'svg', 'math', 'nav'};

bool _hasBlock(dom.Element e) => e.children.any((c) => _blockTags.contains(c.localName) || _hasBlock(c));

void _walk(dom.Element e, List<String> out, void Function(String) onHeading) {
  for (final c in e.children) {
    final name = c.localName ?? '';
    if (_skipTags.contains(name)) continue;
    if (_hasBlock(c)) {
      _walk(c, out, onHeading);
      continue;
    }
    final t = c.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) continue;
    if (RegExp(r'^h[1-6]$').hasMatch(name)) onHeading(t);
    out.add(t);
  }
}

// ---------------------------------------------------------------- Texto

final _sentEnd = RegExp(r'[.!?…:»"”)\]]$');
final _pageNum = RegExp(r'^\d{1,4}$');

/// Une las líneas cortadas (típico de PDF y TXT) en párrafos reales.
List<String> reflow(String text) {
  final lines = text
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList();
  var maxLen = 0;
  for (final l in lines) {
    if (l.length > maxLen && l.length < 220) maxLen = l.length;
  }
  final out = <String>[];
  var b = '';
  void flush() {
    if (b.trim().isNotEmpty) out.addAll(splitLong(b.trim()));
    b = '';
  }

  for (final l in lines) {
    if (l.isEmpty) {
      flush();
      continue;
    }
    if (_pageNum.hasMatch(l)) continue;
    final startsLower = l[0].toLowerCase() == l[0] && l[0].toUpperCase() != l[0];
    if (b.endsWith('-') && startsLower) {
      b = b.substring(0, b.length - 1) + l;
    } else {
      b = b.isEmpty ? l : '$b $l';
    }
    if (_sentEnd.hasMatch(l) && (l.length >= 220 || maxLen == 0 || l.length < maxLen * 0.82)) flush();
  }
  flush();
  return out;
}

final _sentences = RegExp(r'[^.!?…]+[.!?…]+["»”)]*\s*|[^.!?…]+$');

/// Corta párrafos muy largos en grupos de oraciones (mejor para la voz).
List<String> splitLong(String p) {
  if (p.length <= 700) return [p];
  final out = <String>[];
  var cur = '';
  for (final m in _sentences.allMatches(p)) {
    var s = m.group(0)!;
    while (s.length > 700) {
      final cut = s.lastIndexOf(' ', 450);
      final at = cut > 100 ? cut : 450;
      if (cur.isNotEmpty) {
        out.add(cur.trim());
        cur = '';
      }
      out.add(s.substring(0, at).trim());
      s = s.substring(at);
    }
    if ((cur + s).length > 500 && cur.isNotEmpty) {
      out.add(cur.trim());
      cur = '';
    }
    cur += s;
  }
  if (cur.trim().isNotEmpty) out.add(cur.trim());
  return out;
}

final _headingRx = RegExp(
  r'^(cap[ií]tulo|chapter|parte|part|libro|book|pr[oó]logo|prologue|ep[ií]logo|epilogue|introducci[oó]n|introduction|pref[aá]cio|preface)\b',
  caseSensitive: false,
);

List<Map<String, dynamic>> _detectHeadings(List<String> paras) {
  final s = <Map<String, dynamic>>[];
  for (var i = 0; i < paras.length; i++) {
    final p = paras[i];
    if (p.length < 80 && _headingRx.hasMatch(p)) s.add({'t': p, 's': i});
  }
  return _clean(s, paras.length);
}

/// Ordena, saca duplicados y asegura que la primera sección empiece en 0.
List<Map<String, dynamic>> _clean(List<Map<String, dynamic>> s, int total) {
  if (total == 0) return s;
  s.sort((a, b) => (a['s'] as int).compareTo(b['s'] as int));
  final out = <Map<String, dynamic>>[];
  for (final x in s) {
    final st = (x['s'] as int).clamp(0, total - 1);
    if (out.isNotEmpty && out.last['s'] == st) continue;
    out.add({'t': x['t'], 's': st});
  }
  if (out.isEmpty || out.first['s'] != 0) out.insert(0, {'t': 'Inicio', 's': 0});
  return out;
}

const _en = {'the', 'and', 'of', 'to', 'is', 'that', 'with', 'was', 'for', 'you', 'he', 'she', 'it', 'in', 'his', 'her', 'they', 'this', 'are', 'have'};
const _es = {'el', 'la', 'de', 'que', 'y', 'los', 'las', 'en', 'un', 'una', 'por', 'con', 'es', 'se', 'del', 'su', 'para', 'como', 'pero', 'más'};

String detectLang(List<String> paras) {
  var en = 0, es = 0;
  final take = paras.length < 400 ? paras.length : 400;
  final start = paras.length > 600 ? 100 : 0; // saltea portada e índice
  for (var i = start; i < (start + take).clamp(0, paras.length); i++) {
    for (final w in paras[i].toLowerCase().split(RegExp(r"[^a-záéíóúñü']+"))) {
      if (_en.contains(w)) en++;
      if (_es.contains(w)) es++;
    }
  }
  if (en == 0 && es == 0) return 'otro';
  return en > es * 1.3 ? 'en' : (es >= en ? 'es' : 'otro');
}
