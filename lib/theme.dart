import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppTheme { auto, claro, sepia, noche }

const themeNames = {
  AppTheme.auto: 'Automático',
  AppTheme.claro: 'Claro',
  AppTheme.sepia: 'Sepia',
  AppTheme.noche: 'Noche',
};

@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.fg,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.hl,
    required this.word,
    required this.brightness,
  });

  final Color bg, surface, surface2, fg, muted, line, accent, onAccent, hl, word;
  final Brightness brightness;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) =>
      other is Palette ? (t < .5 ? this : other) : this;
}

const _claro = Palette(
  bg: Color(0xFFF4F5F7),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFEBEDF1),
  fg: Color(0xFF121417),
  muted: Color(0xFF6A717C),
  line: Color(0xFFE1E4E9),
  accent: Color(0xFFF2643A),
  onAccent: Color(0xFFFFFFFF),
  hl: Color(0xFFFFEAE2),
  word: Color(0xFFFFD3C3),
  brightness: Brightness.light,
);

const _sepia = Palette(
  bg: Color(0xFFF3ECDF),
  surface: Color(0xFFFBF7EF),
  surface2: Color(0xFFECE2D0),
  fg: Color(0xFF3B2F23),
  muted: Color(0xFF7D6C59),
  line: Color(0xFFE1D5BF),
  accent: Color(0xFFC4532F),
  onAccent: Color(0xFFFFFFFF),
  hl: Color(0xFFF1DEC6),
  word: Color(0xFFE8C7A0),
  brightness: Brightness.light,
);

const _noche = Palette(
  bg: Color(0xFF0E0F12),
  surface: Color(0xFF17191E),
  surface2: Color(0xFF21242B),
  fg: Color(0xFFF1F2F4),
  muted: Color(0xFF9AA1AC),
  line: Color(0xFF2A2E36),
  accent: Color(0xFFFF8A5B),
  onAccent: Color(0xFF1C0F09),
  hl: Color(0xFF2D201A),
  word: Color(0xFF5C3524),
  brightness: Brightness.dark,
);

Palette paletteFor(AppTheme t) {
  switch (t) {
    case AppTheme.sepia:
      return _sepia;
    case AppTheme.noche:
      return _noche;
    case AppTheme.claro:
    case AppTheme.auto:
      return _claro;
  }
}

Palette get nightPalette => _noche;

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    surface: p.surface,
    onSurface: p.fg,
    outlineVariant: p.line,
    secondaryContainer: p.hl,
    onSecondaryContainer: p.fg,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    fontFamily: GoogleFonts.manrope().fontFamily,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    extensions: [p],
    dividerColor: p.line,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.fg,
      contentTextStyle: TextStyle(color: p.bg, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: p.line),
        foregroundColor: p.fg,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.line,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : null),
    ),
  );
  return base.copyWith(textTheme: base.textTheme.apply(bodyColor: p.fg, displayColor: p.fg));
}

Palette pal(BuildContext c) => Theme.of(c).extension<Palette>()!;

/// Letra de lectura (serif).
TextStyle serif({double size = 18, FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
    GoogleFonts.literata(fontSize: size, fontWeight: weight, color: color, height: height);

/// Letra del texto del libro (la elige el usuario).
TextStyle readingStyle(String family, {double size = 19, double height = 1.7, Color? color, FontWeight weight = FontWeight.w400}) {
  try {
    return GoogleFonts.getFont(family, fontSize: size, height: height, color: color, fontWeight: weight);
  } catch (_) {
    return serif(size: size, height: height, color: color, weight: weight);
  }
}

TextStyle label(Color color) =>
    TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: color);

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
