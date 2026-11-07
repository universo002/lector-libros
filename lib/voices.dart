import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _base = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

/// Una voz natural (modelo Piper) que se descarga una vez y funciona sin internet.
class VoiceInfo {
  final String id;
  final String name;
  final String region;
  final String quality;
  final String lang; // 'es' o 'en'
  final String dir; // nombre de la carpeta y del archivo .tar.bz2
  final String onnx;
  final int sid;
  final int approxMb;
  final String description;

  const VoiceInfo({
    required this.id,
    required this.name,
    required this.region,
    required this.quality,
    required this.lang,
    required this.dir,
    required this.onnx,
    this.sid = 0,
    required this.approxMb,
    required this.description,
  });

  String get url => '$_base/$dir.tar.bz2';
}

const voiceCatalog = <VoiceInfo>[
  VoiceInfo(
    id: 'daniela',
    name: 'Daniela',
    region: 'Argentina',
    quality: 'Alta calidad',
    lang: 'es',
    dir: 'vits-piper-es_AR-daniela-high',
    onnx: 'es_AR-daniela-high.onnx',
    approxMb: 115,
    description: 'Voz rioplatense, clara y cálida. Ideal para narrar.',
  ),
  VoiceInfo(
    id: 'miro',
    name: 'Miro',
    region: 'España',
    quality: 'Alta calidad',
    lang: 'es',
    dir: 'vits-piper-es_ES-miro-high',
    onnx: 'es_ES-miro-high.onnx',
    approxMb: 115,
    description: 'Castellano de España, pausado.',
  ),
  VoiceInfo(
    id: 'davefx',
    name: 'Dave',
    region: 'España',
    quality: 'Calidad media',
    lang: 'es',
    dir: 'vits-piper-es_ES-davefx-medium',
    onnx: 'es_ES-davefx-medium.onnx',
    approxMb: 65,
    description: 'Buena para diálogos, contrasta con Daniela.',
  ),
  VoiceInfo(
    id: 'claude_mx',
    name: 'Claude',
    region: 'México',
    quality: 'Alta calidad',
    lang: 'es',
    dir: 'vits-piper-es_MX-claude-high',
    onnx: 'es_MX-claude-high.onnx',
    approxMb: 115,
    description: 'Español neutro de México.',
  ),
  VoiceInfo(
    id: 'ald',
    name: 'Ald',
    region: 'México',
    quality: 'Calidad media',
    lang: 'es',
    dir: 'vits-piper-es_MX-ald-medium',
    onnx: 'es_MX-ald-medium.onnx',
    approxMb: 65,
    description: 'Español de México, tono firme.',
  ),
  VoiceInfo(
    id: 'sharvard_a',
    name: 'Sharvard A',
    region: 'España',
    quality: 'Calidad media',
    lang: 'es',
    dir: 'vits-piper-es_ES-sharvard-medium',
    onnx: 'es_ES-sharvard-medium.onnx',
    sid: 0,
    approxMb: 80,
    description: 'Un modelo con dos voces (A y B): se descargan juntas.',
  ),
  VoiceInfo(
    id: 'sharvard_b',
    name: 'Sharvard B',
    region: 'España',
    quality: 'Calidad media',
    lang: 'es',
    dir: 'vits-piper-es_ES-sharvard-medium',
    onnx: 'es_ES-sharvard-medium.onnx',
    sid: 1,
    approxMb: 80,
    description: 'La segunda voz del modelo Sharvard.',
  ),
  VoiceInfo(
    id: 'ryan',
    name: 'Ryan',
    region: 'Inglés (EE. UU.)',
    quality: 'Calidad media',
    lang: 'en',
    dir: 'vits-piper-en_US-ryan-medium',
    onnx: 'en_US-ryan-medium.onnx',
    approxMb: 65,
    description: 'Para escuchar libros en inglés sin traducir.',
  ),
];

VoiceInfo? voiceById(String id) {
  for (final v in voiceCatalog) {
    if (v.id == id) return v;
  }
  return null;
}

/// Descarga, guarda y borra voces.
class Voices extends ChangeNotifier {
  Voices._();
  static final Voices I = Voices._();

  late String root;
  final Map<String, double> progress = {}; // por carpeta (dir), 0..1; -1 = descomprimiendo
  final Map<String, String> errors = {};

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    root = '${docs.path}/voces';
    await Directory(root).create(recursive: true);
  }

  String modelPath(VoiceInfo v) => '$root/${v.dir}/${v.onnx}';
  String tokensPath(VoiceInfo v) => '$root/${v.dir}/tokens.txt';
  String dataDir(VoiceInfo v) => '$root/${v.dir}/espeak-ng-data';

  bool isReady(VoiceInfo? v) {
    if (v == null) return false;
    return File(modelPath(v)).existsSync() &&
        File(tokensPath(v)).existsSync() &&
        Directory(dataDir(v)).existsSync();
  }

  bool isDownloading(VoiceInfo v) => progress.containsKey(v.dir);

  Future<bool> download(VoiceInfo v) async {
    if (isReady(v)) return true;
    if (isDownloading(v)) return false;
    progress[v.dir] = 0;
    errors.remove(v.dir);
    notifyListeners();
    final tmp = File('$root/${v.dir}.tar.bz2');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(v.url)));
      if (res.statusCode != 200) throw Exception('El servidor respondió ${res.statusCode}');
      final total = res.contentLength ?? v.approxMb * 1024 * 1024;
      final sink = tmp.openWrite();
      var got = 0;
      var lastNotify = DateTime.now();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 250) {
          progress[v.dir] = (got / total).clamp(0.0, 0.99).toDouble();
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.close();
      progress[v.dir] = -1;
      notifyListeners();
      final archivePath = tmp.path;
      final out = root;
      await Isolate.run(() => _extract(archivePath, out));
      if (await tmp.exists()) await tmp.delete();
      if (!isReady(v)) throw Exception('La voz descargada está incompleta');
      return true;
    } catch (e) {
      errors[v.dir] = 'No se pudo descargar. Revisá tu conexión e intentá de nuevo.';
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    } finally {
      client.close();
      progress.remove(v.dir);
      notifyListeners();
    }
  }

  Future<void> remove(VoiceInfo v) async {
    final d = Directory('$root/${v.dir}');
    if (await d.exists()) await d.delete(recursive: true);
    notifyListeners();
  }
}

void _extract(String archivePath, String outDir) {
  final bz = File(archivePath).readAsBytesSync();
  final tarBytes = BZip2Decoder().decodeBytes(bz);
  final arc = TarDecoder().decodeBytes(tarBytes);
  for (final f in arc.files) {
    final name = f.name;
    if (name.contains('..')) continue;
    final path = '$outDir/$name';
    if (f.isFile) {
      final out = File(path);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(f.content as List<int>);
    } else {
      Directory(path).createSync(recursive: true);
    }
  }
}
