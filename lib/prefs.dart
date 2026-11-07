import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Cómo se leen los diálogos de los personajes.
enum DialogueMode { igual, tono, otraVoz, personajes }

enum LibrarySort { recientes, titulo, progreso }

enum LibraryFilter { todos, escuchando, sinEmpezar, terminados }

const readingFonts = ['Literata', 'Lora', 'Atkinson Hyperlegible', 'Merriweather'];
const readingFontNames = ['Literata', 'Lora', 'Fácil lectura', 'Merriweather'];

/// Ajustes del usuario que se guardan entre sesiones.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final Prefs I = Prefs._();

  SharedPreferences? _sp;

  // Lectura en pantalla
  double fontSize = 19;
  double lineHeight = 1.7;
  int readingFont = 0;
  AppTheme theme = AppTheme.auto;
  bool followText = true;
  bool focusMode = false;

  // Voz
  bool narratorMale = false; // false = Mónica narra; true = la voz de hombre narra
  double speed = 0.9; // velocidad general
  double speedFemale = 1.0; // ajuste fino de Mónica
  double speedMale = 1.0; // ajuste fino de la voz de hombre
  DialogueMode dialogueMode = DialogueMode.personajes;
  int pauseLevel = 1; // 0 cortas, 1 normales, 2 largas
  bool expressive = true;

  // Biblioteca y metas
  LibrarySort sort = LibrarySort.recientes;
  LibraryFilter filter = LibraryFilter.todos;
  int dailyGoal = 20; // minutos

  Future<void> load() async {
    final s = await SharedPreferences.getInstance();
    _sp = s;
    fontSize = s.getDouble('fontSize') ?? 19;
    lineHeight = s.getDouble('lineHeight') ?? 1.7;
    readingFont = (s.getInt('readingFont') ?? 0).clamp(0, readingFonts.length - 1);
    final t = s.getInt('theme2') ?? 0;
    theme = AppTheme.values[t.clamp(0, AppTheme.values.length - 1)];
    followText = s.getBool('followText') ?? true;
    focusMode = s.getBool('focusMode') ?? false;
    narratorMale = s.getBool('narratorMale') ?? false;
    speed = s.getDouble('speed3') ?? 0.9;
    speedFemale = s.getDouble('speedFemale') ?? 1.0;
    speedMale = s.getDouble('speedMale') ?? 1.0;
    final dm = s.getInt('dialogueMode4') ?? DialogueMode.personajes.index;
    dialogueMode = DialogueMode.values[dm.clamp(0, DialogueMode.values.length - 1)];
    pauseLevel = (s.getInt('pauseLevel') ?? 1).clamp(0, 2);
    expressive = s.getBool('expressive') ?? true;
    sort = LibrarySort.values[(s.getInt('sort') ?? 0).clamp(0, LibrarySort.values.length - 1)];
    filter = LibraryFilter.values[(s.getInt('filter') ?? 0).clamp(0, LibraryFilter.values.length - 1)];
    dailyGoal = s.getInt('dailyGoal') ?? 20;
  }

  void _d(String k, double v) => _sp?.setDouble(k, v);
  void _i(String k, int v) => _sp?.setInt(k, v);
  void _b(String k, bool v) => _sp?.setBool(k, v);

  void setFontSize(double v) {
    fontSize = v;
    _d('fontSize', v);
    notifyListeners();
  }

  void setLineHeight(double v) {
    lineHeight = v;
    _d('lineHeight', v);
    notifyListeners();
  }

  void setReadingFont(int v) {
    readingFont = v;
    _i('readingFont', v);
    notifyListeners();
  }

  void setTheme(AppTheme t) {
    theme = t;
    _i('theme2', t.index);
    notifyListeners();
  }

  void setFollowText(bool v) {
    followText = v;
    _b('followText', v);
    notifyListeners();
  }

  void setFocusMode(bool v) {
    focusMode = v;
    _b('focusMode', v);
    notifyListeners();
  }

  void setNarratorMale(bool v) {
    narratorMale = v;
    _b('narratorMale', v);
    notifyListeners();
  }

  void setSpeed(double v) {
    speed = v;
    _d('speed3', v);
    notifyListeners();
  }

  void setSpeedFemale(double v) {
    speedFemale = v;
    _d('speedFemale', v);
    notifyListeners();
  }

  void setSpeedMale(double v) {
    speedMale = v;
    _d('speedMale', v);
    notifyListeners();
  }

  void setDialogueMode(DialogueMode m) {
    dialogueMode = m;
    _i('dialogueMode4', m.index);
    notifyListeners();
  }

  void setPauseLevel(int v) {
    pauseLevel = v;
    _i('pauseLevel', v);
    notifyListeners();
  }

  void setExpressive(bool v) {
    expressive = v;
    _b('expressive', v);
    notifyListeners();
  }

  void setSort(LibrarySort v) {
    sort = v;
    _i('sort', v.index);
    notifyListeners();
  }

  void setFilter(LibraryFilter v) {
    filter = v;
    _i('filter', v.index);
    notifyListeners();
  }

  void setDailyGoal(int v) {
    dailyGoal = v;
    _i('dailyGoal', v);
    notifyListeners();
  }
}
