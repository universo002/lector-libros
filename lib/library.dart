import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Guarda los libros en el teléfono: un índice liviano y un archivo por libro.
class Library extends ChangeNotifier {
  Library._();
  static final Library I = Library._();

  late Directory _dir;
  final List<BookMeta> books = [];
  Timer? _saveTimer;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/biblioteca');
    if (!await _dir.exists()) await _dir.create(recursive: true);
    final f = File('${_dir.path}/indice.json');
    if (await f.exists()) {
      try {
        final list = jsonDecode(await f.readAsString()) as List;
        books
          ..clear()
          ..addAll(list.map((m) => BookMeta.fromJson(Map<String, dynamic>.from(m as Map))));
      } catch (_) {}
    }
    _sort();
  }

  void _sort() => books.sort((a, b) => b.opened.compareTo(a.opened));

  /// Marca cambios y guarda el índice un segundo después (agrupa escrituras).
  void touch() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), saveNow);
    notifyListeners();
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final data = jsonEncode(books.map((b) => b.toJson()).toList());
    await File('${_dir.path}/indice.json').writeAsString(data);
  }

  String coverPath(String id) => '${_dir.path}/$id.cover.jpg';
  String _contentPath(String id) => '${_dir.path}/$id.json';
  String _trPath(String id) => '${_dir.path}/$id.es.json';

  Future<BookMeta> add(Map<String, dynamic> r, {Uint8List? cover}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final paras = (r['paras'] as List).cast<String>();
    final secs = (r['sections'] as List).map((s) => Map<String, dynamic>.from(s as Map)).toList();
    final encoded = await Isolate.run(() => jsonEncode({'sections': secs, 'paras': paras}));
    await File(_contentPath(id)).writeAsString(encoded);
    var chars = 0;
    for (final p in paras) {
      chars += p.length;
    }
    final title = r['title'] as String;
    final meta = BookMeta(
      id: id,
      title: title,
      author: (r['author'] ?? '') as String,
      format: (r['format'] ?? '') as String,
      lang: (r['lang'] ?? 'es') as String,
      paraCount: paras.length,
      chars: chars,
      pages: ((r['pages'] ?? 0) as num).toInt(),
      hue: title.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) % 360),
    );
    final c = cover ?? (r['cover'] is Uint8List ? r['cover'] as Uint8List : null);
    if (c != null && c.isNotEmpty) {
      try {
        await File(coverPath(id)).writeAsBytes(c);
        meta.hasCover = true;
      } catch (_) {}
    }
    books.insert(0, meta);
    await saveNow();
    notifyListeners();
    return meta;
  }

  Future<BookContent> content(String id) async {
    final s = await File(_contentPath(id)).readAsString();
    final m = await Isolate.run(() => jsonDecode(s) as Map<String, dynamic>);
    return BookContent.fromJson(m);
  }

  Future<List<String?>?> translation(String id) async {
    final f = File(_trPath(id));
    if (!await f.exists()) return null;
    try {
      final s = await f.readAsString();
      final list = await Isolate.run(() => jsonDecode(s) as List);
      return list.map((e) => e as String?).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTranslation(String id, List<String?> t) async {
    final copy = List<String?>.of(t);
    final s = await Isolate.run(() => jsonEncode(copy));
    await File(_trPath(id)).writeAsString(s);
  }

  Future<void> remove(String id) async {
    books.removeWhere((b) => b.id == id);
    for (final p in [_contentPath(id), _trPath(id), coverPath(id)]) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
    await saveNow();
    notifyListeners();
  }
}
