import 'dart:io';

import 'package:flutter/material.dart';

import '../library.dart';
import '../models.dart';
import '../prefs.dart';
import '../reader_engine.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import 'sheets.dart';

/// Reproductor a pantalla completa, con la portada grande.
Future<void> showPlayerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.96, child: _PlayerSheet()),
  );
}

class _PlayerSheet extends StatefulWidget {
  const _PlayerSheet();
  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  Color? _tint;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _loadTint();
  }

  Future<void> _loadTint() async {
    final m = ReaderEngine.I.meta;
    if (m == null) return;
    if (!m.hasCover) {
      setState(() => _tint = HSLColor.fromAHSL(1, m.hue.toDouble(), 0.45, 0.32).toColor());
      return;
    }
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(FileImage(File(Library.I.coverPath(m.id))), width: 120),
        brightness: Brightness.dark,
      );
      if (mounted) setState(() => _tint = scheme.primaryContainer);
    } catch (_) {
      if (mounted) setState(() => _tint = HSLColor.fromAHSL(1, m.hue.toDouble(), 0.45, 0.32).toColor());
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = ReaderEngine.I;
    final tint = _tint ?? const Color(0xFF2A2F38);
    const fg = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.7);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(tint, Colors.black, 0.15)!, Color.lerp(tint, Colors.black, 0.78)!],
        ),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([e, Prefs.I]),
        builder: (context, _) {
          final m = e.meta;
          final c = e.content;
          if (m == null || c == null) return const SizedBox.shrink();
          final n = c.paras.length;
          final shown = (_drag ?? e.idx.toDouble()).clamp(0, (n - 1).toDouble()).toDouble();
          final pct = n <= 1 ? 0 : (shown / (n - 1) * 100).round();
          final dragSection = c.sections[c.sectionOf(shown.round())].title;
          final w = MediaQuery.of(context).size.width;
          final coverW = (w * 0.62).clamp(160.0, 300.0).toDouble();
          return SafeArea(
            top: false,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3))),
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 30),
                ),
                Expanded(
                  child: Text(e.playing ? 'ESCUCHANDO' : 'EN PAUSA',
                      textAlign: TextAlign.center, style: label(Colors.white.withValues(alpha: 0.75))),
                ),
                const SizedBox(width: 48),
              ]),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(children: [
                    const SizedBox(height: 12),
                    Center(child: BookCover(meta: m, width: coverW, radius: 16)),
                    const SizedBox(height: 28),
                    Text(m.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serif(size: 23, weight: FontWeight.w600, color: fg, height: 1.2)),
                    const SizedBox(height: 6),
                    Text(_drag != null ? dragSection : e.sectionTitle,
                        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 15)),
                    const SizedBox(height: 18),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: fg,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: fg,
                        overlayColor: Colors.white12,
                      ),
                      child: Slider(
                        value: shown,
                        min: 0,
                        max: (n - 1).clamp(1, 1 << 30).toDouble(),
                        onChanged: (v) => setState(() => _drag = v),
                        onChangeEnd: (v) {
                          setState(() => _drag = null);
                          e.jumpTo(v.round());
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        Text('$pct %', style: TextStyle(color: muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
                        const Spacer(),
                        Text('Capítulo: ${fmtMinutes(e.sectionRemainingMinutes)}', style: TextStyle(color: muted, fontSize: 12.5)),
                        const Spacer(),
                        Text('−${fmtMinutes(e.remainingMinutes)}',
                            style: TextStyle(color: muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      IconButton(
                        tooltip: 'Capítulo anterior',
                        onPressed: () => e.skipSection(-1),
                        icon: const Icon(Icons.skip_previous_rounded, color: fg, size: 34),
                      ),
                      IconButton(
                        tooltip: 'Párrafo anterior',
                        onPressed: e.prev,
                        icon: const Icon(Icons.replay_rounded, color: fg, size: 32),
                      ),
                      SizedBox(
                        width: 78,
                        height: 78,
                        child: Material(
                          color: fg,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => playOrAskVoice(context),
                            child: Center(
                              child: e.loading && e.playing
                                  ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                                  : Icon(e.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 46),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Párrafo siguiente',
                        onPressed: e.next,
                        icon: const Icon(Icons.forward_rounded, color: fg, size: 32),
                      ),
                      IconButton(
                        tooltip: 'Capítulo siguiente',
                        onPressed: () => e.skipSection(1),
                        icon: const Icon(Icons.skip_next_rounded, color: fg, size: 34),
                      ),
                    ]),
                    const SizedBox(height: 26),
                    Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                      _GlassPill(
                        icon: Icons.speed_rounded,
                        text: '${Prefs.I.speed.toStringAsFixed(Prefs.I.speed % 1 == 0 ? 1 : 2)}×',
                        onTap: () => showSpeedSheet(context),
                      ),
                      _GlassPill(
                        icon: Icons.record_voice_over_outlined,
                        text: e.currentVoiceLabel,
                        onTap: () => showVoiceSheet(context),
                      ),
                      _GlassPill(
                        icon: e.sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                        text: e.sleepAt != null
                            ? '${e.sleepAt!.difference(DateTime.now()).inMinutes + 1} min'
                            : (e.sleepEndOfSection ? 'Fin del capítulo' : 'Temporizador'),
                        active: e.sleepActive,
                        onTap: () => showSleepSheet(context),
                      ),
                      if (m.isEnglish)
                        _GlassPill(
                          icon: Icons.translate_rounded,
                          text: m.useTranslation ? 'Español' : 'Inglés',
                          onTap: () => showTranslateSheet(context),
                        ),
                    ]),
                    const SizedBox(height: 24),
                    _NowReading(meta: m),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _GlassPill({required this.icon, required this.text, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: active ? 0.28 : 0.14),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(text,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// La frase que se está leyendo, en grande.
class _NowReading extends StatelessWidget {
  final BookMeta meta;
  const _NowReading({required this.meta});

  @override
  Widget build(BuildContext context) {
    final e = ReaderEngine.I;
    return ValueListenableBuilder<HL?>(
      valueListenable: e.hl,
      builder: (_, h, __) {
        if (h == null || e.content == null) return const SizedBox.shrink();
        final t = e.textAt(h.para);
        if (h.end > t.length || h.end <= h.start) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
          child: Text(t.substring(h.start, h.end), style: serif(size: 18, color: Colors.white, height: 1.55)),
        );
      },
    );
  }
}
