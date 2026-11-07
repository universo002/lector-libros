import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiempo de escucha por día, racha y meta diaria.
class Stats extends ChangeNotifier {
  Stats._();
  static final Stats I = Stats._();

  SharedPreferences? _sp;
  final Map<String, int> _secs = {}; // 'aaaa-mm-dd' -> segundos
  int finishedBooks = 0;
  int _unsaved = 0;

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    final s = await SharedPreferences.getInstance();
    _sp = s;
    final raw = s.getString('stats');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((k, v) => _secs[k] = (v as num).toInt());
      } catch (_) {}
    }
    finishedBooks = s.getInt('finishedBooks') ?? 0;
  }

  void addSeconds(int s) {
    final k = keyFor(DateTime.now());
    _secs[k] = (_secs[k] ?? 0) + s;
    _unsaved += s;
    if (_unsaved >= 30) save();
    notifyListeners();
  }

  void save() {
    _unsaved = 0;
    _sp?.setString('stats', jsonEncode(_secs));
  }

  void bookFinished() {
    finishedBooks++;
    _sp?.setInt('finishedBooks', finishedBooks);
    notifyListeners();
  }

  int minutesOn(DateTime d) => ((_secs[keyFor(d)] ?? 0) / 60).floor();

  int get todayMinutes => minutesOn(DateTime.now());

  int get totalMinutes => (_secs.values.fold<int>(0, (a, b) => a + b) / 60).floor();

  /// Días seguidos escuchando al menos 1 minuto (hoy cuenta si ya escuchaste).
  int get streak {
    var d = DateTime.now();
    if (minutesOn(d) < 1) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (minutesOn(d) >= 1) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Minutos de los últimos 7 días (del más viejo a hoy).
  List<int> get lastWeek {
    final now = DateTime.now();
    return [for (var i = 6; i >= 0; i--) minutesOn(now.subtract(Duration(days: i)))];
  }
}
