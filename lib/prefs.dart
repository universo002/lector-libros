import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Ajustes del usuario que se guardan entre sesiones.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final Prefs I = Prefs._();

  SharedPreferences? _sp;
  double fontSize = 19;
  double speed = 1.0;
  ReadingTheme theme = ReadingTheme.claro;
  bool wordHighlight = true;
  String? voiceName;
  String? voiceLocale;

  Future<void> load() async {
    final s = await SharedPreferences.getInstance();
    _sp = s;
    fontSize = s.getDouble('fontSize') ?? 19;
    speed = s.getDouble('speed') ?? 1.0;
    final t = s.getInt('theme') ?? 0;
    theme = ReadingTheme.values[t.clamp(0, ReadingTheme.values.length - 1)];
    wordHighlight = s.getBool('wordHighlight') ?? true;
    voiceName = s.getString('voiceName');
    voiceLocale = s.getString('voiceLocale');
  }

  void setFontSize(double v) {
    fontSize = v;
    _sp?.setDouble('fontSize', v);
    notifyListeners();
  }

  void setSpeed(double v) {
    speed = v;
    _sp?.setDouble('speed', v);
    notifyListeners();
  }

  void setTheme(ReadingTheme t) {
    theme = t;
    _sp?.setInt('theme', t.index);
    notifyListeners();
  }

  void setWordHighlight(bool v) {
    wordHighlight = v;
    _sp?.setBool('wordHighlight', v);
    notifyListeners();
  }

  void setVoice(String name, String locale) {
    voiceName = name;
    voiceLocale = locale;
    _sp?.setString('voiceName', name);
    _sp?.setString('voiceLocale', locale);
    notifyListeners();
  }
}
