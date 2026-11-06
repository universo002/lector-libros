import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'library.dart';
import 'models.dart';

/// Traducción inglés → español en el mismo celular (Google ML Kit).
/// Gratis y sin internet, salvo la primera descarga del modelo (~30 MB).
class Translator extends ChangeNotifier {
  Translator._();
  static final Translator I = Translator._();

  OnDeviceTranslator? _tl;
  bool modelReady = false;
  bool running = false;
  bool _cancel = false;
  String? bookId;
  int done = 0, total = 0;
  String status = '';

  Future<bool> ensureModel() async {
    if (modelReady && _tl != null) return true;
    final mm = OnDeviceTranslatorModelManager();
    try {
      final need = <String>[];
      for (final l in [TranslateLanguage.english, TranslateLanguage.spanish]) {
        if (!await mm.isModelDownloaded(l.bcpCode)) need.add(l.bcpCode);
      }
      if (need.isNotEmpty) {
        status = 'Descargando el traductor (unos 30 MB, solo la primera vez)…';
        notifyListeners();
        for (final c in need) {
          await mm.downloadModel(c, isWifiRequired: false);
        }
      }
      _tl ??= OnDeviceTranslator(sourceLanguage: TranslateLanguage.english, targetLanguage: TranslateLanguage.spanish);
      modelReady = true;
      return true;
    } catch (_) {
      status = 'No se pudo descargar el traductor. Revisá tu conexión e intentá de nuevo.';
      notifyListeners();
      return false;
    }
  }

  Future<String?> translateOne(String text) async {
    final tl = _tl;
    if (!modelReady || tl == null) return null;
    try {
      return await tl.translateText(text);
    } catch (_) {
      return null;
    }
  }

  /// Traduce el libro entero empezando por [from] (donde estás leyendo),
  /// y guarda el avance cada tanto para poder retomarlo.
  Future<void> translateBook(BookMeta meta, BookContent c, List<String?> tr, int from, VoidCallback onChunk) async {
    if (running) return;
    running = true;
    _cancel = false;
    bookId = meta.id;
    total = c.paras.length;
    done = tr.where((x) => x != null).length;
    notifyListeners();
    if (!await ensureModel()) {
      running = false;
      notifyListeners();
      return;
    }
    status = 'Traduciendo…';
    notifyListeners();
    final order = [for (var i = from; i < total; i++) i, for (var i = 0; i < from; i++) i];
    var sinceSave = 0;
    for (final i in order) {
      if (_cancel) break;
      if (tr[i] != null) continue;
      final t = await translateOne(c.paras[i]);
      if (t == null) continue;
      tr[i] = t;
      done++;
      sinceSave++;
      if (sinceSave % 20 == 0) {
        meta.translated = done;
        notifyListeners();
        onChunk();
      }
      if (sinceSave >= 200) {
        sinceSave = 0;
        await Library.I.saveTranslation(meta.id, tr);
        Library.I.touch();
      }
    }
    meta.translated = done;
    await Library.I.saveTranslation(meta.id, tr);
    Library.I.touch();
    running = false;
    status = done >= total ? 'Traducción completa' : 'Traducción en pausa';
    notifyListeners();
    onChunk();
  }

  void cancel() => _cancel = true;
}
