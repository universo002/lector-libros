import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'prefs.dart';
import 'reader_engine.dart';
import 'screens/library_screen.dart';
import 'stats.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.I.load();
  await Stats.I.load();
  await Library.I.init();
  await _cleanOldVoices();
  await ReaderEngine.I.init();
  try {
    final handler = await AudioService.init(
      builder: () => ReaderAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.banessa.lector.audio',
        androidNotificationChannelName: 'Lectura en voz alta',
        androidNotificationOngoing: true,
      ),
    );
    ReaderEngine.I.attachHandler(handler);
  } catch (_) {
    // Si fallan los controles de la pantalla bloqueada, la app sigue andando igual.
  }
  runApp(const LectorApp());
}

/// Borra las voces de la versión anterior para liberar espacio (unos 180 MB).
Future<void> _cleanOldVoices() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/voces');
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

class LectorApp extends StatelessWidget {
  const LectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (context, _) {
        final t = Prefs.I.theme;
        final light = paletteFor(t == AppTheme.sepia ? AppTheme.sepia : AppTheme.claro);
        final mode = switch (t) {
          AppTheme.auto => ThemeMode.system,
          AppTheme.noche => ThemeMode.dark,
          _ => ThemeMode.light,
        };
        return MaterialApp(
          title: 'Lector',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(light),
          darkTheme: buildTheme(nightPalette),
          themeMode: mode,
          home: const LibraryScreen(),
        );
      },
    );
  }
}
