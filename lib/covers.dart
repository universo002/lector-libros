import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Dibuja la primera página de un PDF como imagen, para usarla de portada.
Future<Uint8List?> renderPdfCover(String path) async {
  try {
    final doc = await PdfDocument.openFile(path);
    final page = await doc.getPage(1);
    const w = 600.0;
    final h = page.width > 0 ? w * page.height / page.width : w * 1.5;
    final img = await page.render(width: w, height: h, backgroundColor: '#FFFFFF');
    await page.close();
    await doc.close();
    return img?.bytes;
  } catch (_) {
    return null;
  }
}
