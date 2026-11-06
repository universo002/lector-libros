import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'library.dart';
import 'prefs.dart';
import 'reader_engine.dart';
import 'screens/library_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.I.load();
  await Library.I.init();
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
    // Si fallan los controles de pantalla bloqueada, la app sigue andando igual.
  }
  runApp(const LectorApp());
}

class LectorApp extends StatelessWidget {
  const LectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (context, _) => MaterialApp(
        title: 'Lector',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Prefs.I.theme),
        home: const LibraryScreen(),
      ),
    );
  }
}
