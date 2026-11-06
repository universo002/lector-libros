import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ReadingTheme { claro, sepia, noche }

const themeNames = {
  ReadingTheme.claro: 'Claro',
  ReadingTheme.sepia: 'Sepia',
  ReadingTheme.noche: 'Noche',
};

@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.fg,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.highlight,
    required this.word,
    required this.brightness,
  });

  final Color bg, surface, fg, muted, line, accent, onAccent, highlight, word;
  final Brightness brightness;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) =>
      other is Palette ? (t < .5 ? this : other) : this;
}

Palette paletteFor(ReadingTheme t) {
  switch (t) {
    case ReadingTheme.claro:
      return const Palette(
        bg: Color(0xFFF4F6F5),
        surface: Color(0xFFFFFFFF),
        fg: Color(0xFF1A211E),
        muted: Color(0xFF5E6B66),
        line: Color(0xFFDDE3E0),
        accent: Color(0xFF1F6B57),
        onAccent: Color(0xFFFFFFFF),
        highlight: Color(0xFFE1EEE8),
        word: Color(0xFFB4DDCB),
        brightness: Brightness.light,
      );
    case ReadingTheme.sepia:
      return const Palette(
        bg: Color(0xFFF2EADB),
        surface: Color(0xFFFAF5EA),
        fg: Color(0xFF3A2E22),
        muted: Color(0xFF7A6A58),
        line: Color(0xFFE2D6C0),
        accent: Color(0xFF2F6B50),
        onAccent: Color(0xFFFFFFFF),
        highlight: Color(0xFFEADFC6),
        word: Color(0xFFDCC796),
        brightness: Brightness.light,
      );
    case ReadingTheme.noche:
      return const Palette(
        bg: Color(0xFF0F1513),
        surface: Color(0xFF18201D),
        fg: Color(0xFFE2E9E5),
        muted: Color(0xFF93A29C),
        line: Color(0xFF2A3531),
        accent: Color(0xFF5FC2A2),
        onAccent: Color(0xFF0C1311),
        highlight: Color(0xFF1E302A),
        word: Color(0xFF2F5C4C),
        brightness: Brightness.dark,
      );
  }
}

ThemeData buildTheme(ReadingTheme t) {
  final p = paletteFor(t);
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness)
      .copyWith(primary: p.accent, onPrimary: p.onAccent, surface: p.surface, onSurface: p.fg, outlineVariant: p.line);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
    dividerColor: p.line,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.surface),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.line,
      thumbColor: p.accent,
      trackHeight: 4,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: GoogleFonts.figtree().fontFamily,
      bodyColor: p.fg,
      displayColor: p.fg,
    ),
  );
}

Palette pal(BuildContext c) => Theme.of(c).extension<Palette>()!;

TextStyle serif({double size = 18, FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
    GoogleFonts.literata(fontSize: size, fontWeight: weight, color: color, height: height);

String fmtMinutes(int m) {
  if (m < 1) return 'menos de 1 min';
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

String fmtThousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
