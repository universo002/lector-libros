import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'library.dart';
import 'models.dart';

/// Traducción inglés → español con Google Traductor (necesita internet).
/// Lo traducido se guarda en el celular, así que se traduce una sola vez.
class Translator extends ChangeNotifier {
  Translator._();
  static final Translator I = Translator._();

  bool running = false;
  bool _cancel = false;
  String? bookId;
  int done = 0, total = 0;
  String? error;

  Future<List<String>?> _batch(List<String> texts) async {
    final q = texts.join('\n');
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'en',
      'tl': 'es',
      'dt': 't',
      'q': q,
    });
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final r = await http.get(uri).timeout(const Duration(seconds: 30));
        if (r.statusCode == 200) {
          final data = jsonDecode(utf8.decode(r.bodyBytes));
          final sb = StringBuffer();
          if (data is List && data.isNotEmpty && data[0] is List) {
            for (final s in data[0] as List) {
              if (s is List && s.isNotEmpty && s[0] is String) sb.write(s[0]);
            }
          }
          final full = sb.toString();
          if (texts.length == 1) return [full.trim()];
          final parts = full.split('\n');
          if (parts.length == texts.length) return parts.map((e) => e.trim()).toList();
          return null; // no coincidió la cantidad: se traduce de a uno
        }
        await Future.delayed(Duration(seconds: 2 << attempt));
      } catch (_) {
        await Future.delayed(Duration(seconds: 2 << attempt));
      }
    }
    throw Exception('sin conexión');
  }

  Future<String?> translateOne(String text) async {
    try {
      final r = await _batch([text]);
      return r?.first;
    } catch (_) {
      return null;
    }
  }

  /// Traduce el libro entero empezando donde estás leyendo.
  Future<void> translateBook(BookMeta meta, BookContent c, List<String?> tr, int from, VoidCallback onChunk) async {
    if (running) return;
    running = true;
    _cancel = false;
    error = null;
    bookId = meta.id;
    total = c.paras.length;
    done = tr.where((x) => x != null).length;
    notifyListeners();

    final order = [for (var i = from; i < total; i++) i, for (var i = 0; i < from; i++) i];
    var sinceSave = 0;
    var k = 0;
    try {
      while (k < order.length && !_cancel) {
        // Arma un lote de párrafos sin traducir (hasta ~1500 letras).
        final idxs = <int>[];
        var len = 0;
        while (k < order.length && idxs.length < 40) {
          final i = order[k];
          if (tr[i] != null) {
            k++;
            continue;
          }
          final l = c.paras[i].length;
          if (idxs.isNotEmpty && len + l > 1500) break;
          idxs.add(i);
          len += l;
          k++;
        }
        if (idxs.isEmpty) continue;
        final texts = [for (final i in idxs) c.paras[i].replaceAll('\n', ' ')];
        var res = await _batch(texts);
        if (res == null) {
          res = <String>[];
          for (final t in texts) {
            final one = await _batch([t]);
            res.add(one?.first ?? t);
          }
        }
        for (var j = 0; j < idxs.length; j++) {
          tr[idxs[j]] = res[j];
        }
        done += idxs.length;
        sinceSave += idxs.length;
        meta.translated = done;
        notifyListeners();
        onChunk();
        if (sinceSave >= 150) {
          sinceSave = 0;
          await Library.I.saveTranslation(meta.id, tr);
          Library.I.touch();
        }
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } catch (_) {
      error = 'Se cortó la conexión. Tocá «Seguir traduciendo» cuando tengas internet.';
    }
    meta.translated = done;
    await Library.I.saveTranslation(meta.id, tr);
    Library.I.touch();
    running = false;
    notifyListeners();
    onChunk();
  }

  void cancel() => _cancel = true;
}
