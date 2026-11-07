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
  AppTheme theme = AppTheme.auto;
  bool followText = true;

  // Voces naturales
  String narrator = 'daniela';
  String dialogue = 'davefx';
  bool dialogueVoice = true;
  String english = 'ryan';

  // Voz del iPhone (respaldo)
  bool useSystemVoice = false;
  String? sysVoiceName;
  String? sysVoiceLocale;

  Future<void> load() async {
    final s = await SharedPreferences.getInstance();
    _sp = s;
    fontSize = s.getDouble('fontSize') ?? 19;
    speed = s.getDouble('speed') ?? 1.0;
    final t = s.getInt('theme2') ?? 0;
    theme = AppTheme.values[t.clamp(0, AppTheme.values.length - 1)];
    followText = s.getBool('followText') ?? true;
    narrator = s.getString('narrator') ?? 'daniela';
    dialogue = s.getString('dialogue') ?? 'davefx';
    dialogueVoice = s.getBool('dialogueVoice') ?? true;
    english = s.getString('english') ?? 'ryan';
    useSystemVoice = s.getBool('useSystemVoice') ?? false;
    sysVoiceName = s.getString('voiceName');
    sysVoiceLocale = s.getString('voiceLocale');
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

  void setTheme(AppTheme t) {
    theme = t;
    _sp?.setInt('theme2', t.index);
    notifyListeners();
  }

  void setFollowText(bool v) {
    followText = v;
    _sp?.setBool('followText', v);
    notifyListeners();
  }

  void setNarrator(String id) {
    narrator = id;
    _sp?.setString('narrator', id);
    notifyListeners();
  }

  void setDialogue(String id) {
    dialogue = id;
    _sp?.setString('dialogue', id);
    notifyListeners();
  }

  void setDialogueVoice(bool v) {
    dialogueVoice = v;
    _sp?.setBool('dialogueVoice', v);
    notifyListeners();
  }

  void setEnglish(String id) {
    english = id;
    _sp?.setString('english', id);
    notifyListeners();
  }

  void setUseSystemVoice(bool v) {
    useSystemVoice = v;
    _sp?.setBool('useSystemVoice', v);
    notifyListeners();
  }

  void setSystemVoice(String name, String locale) {
    sysVoiceName = name;
    sysVoiceLocale = locale;
    _sp?.setString('voiceName', name);
    _sp?.setString('voiceLocale', locale);
    notifyListeners();
  }
}
