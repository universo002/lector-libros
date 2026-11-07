import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Cómo se leen los diálogos de los personajes.
enum DialogueMode { igual, tono, otraVoz }

/// Ajustes del usuario que se guardan entre sesiones.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final Prefs I = Prefs._();

  SharedPreferences? _sp;

  double fontSize = 19;
  double speed = 0.9;
  AppTheme theme = AppTheme.auto;
  bool followText = true;

  // Voz
  String? voiceName;
  String? voiceLocale;
  DialogueMode dialogueMode = DialogueMode.tono;
  String? dialogueVoiceName;
  String? dialogueVoiceLocale;
  int pauseLevel = 1; // 0 cortas, 1 normales, 2 largas

  Future<void> load() async {
    final s = await SharedPreferences.getInstance();
    _sp = s;
    fontSize = s.getDouble('fontSize') ?? 19;
    speed = s.getDouble('speed3') ?? 0.9;
    final t = s.getInt('theme2') ?? 0;
    theme = AppTheme.values[t.clamp(0, AppTheme.values.length - 1)];
    followText = s.getBool('followText') ?? true;
    voiceName = s.getString('voiceName');
    voiceLocale = s.getString('voiceLocale');
    final dm = s.getInt('dialogueMode') ?? 1;
    dialogueMode = DialogueMode.values[dm.clamp(0, DialogueMode.values.length - 1)];
    dialogueVoiceName = s.getString('dialogueVoiceName');
    dialogueVoiceLocale = s.getString('dialogueVoiceLocale');
    pauseLevel = (s.getInt('pauseLevel') ?? 1).clamp(0, 2);
  }

  void setFontSize(double v) {
    fontSize = v;
    _sp?.setDouble('fontSize', v);
    notifyListeners();
  }

  void setSpeed(double v) {
    speed = v;
    _sp?.setDouble('speed3', v);
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

  void setVoice(String name, String locale) {
    voiceName = name;
    voiceLocale = locale;
    _sp?.setString('voiceName', name);
    _sp?.setString('voiceLocale', locale);
    notifyListeners();
  }

  void setDialogueMode(DialogueMode m) {
    dialogueMode = m;
    _sp?.setInt('dialogueMode', m.index);
    notifyListeners();
  }

  void setDialogueVoice(String name, String locale) {
    dialogueVoiceName = name;
    dialogueVoiceLocale = locale;
    _sp?.setString('dialogueVoiceName', name);
    _sp?.setString('dialogueVoiceLocale', locale);
    notifyListeners();
  }

  void setPauseLevel(int v) {
    pauseLevel = v;
    _sp?.setInt('pauseLevel', v);
    notifyListeners();
  }
}
