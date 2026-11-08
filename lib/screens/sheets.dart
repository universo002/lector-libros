import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lector_tts/lector_tts.dart';

import '../prefs.dart';
import '../reader_engine.dart';
import '../stats.dart';
import '../theme.dart';
import '../translator.dart';

Future<void> _sheet(BuildContext context, WidgetBuilder builder, {bool tall = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => tall
        ? FractionallySizedBox(heightFactor: 0.9, child: builder(c))
        : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 22), child: builder(c))),
  );
}

Widget _title(BuildContext c, String t, {String? sub}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: pal(c).fg)),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: pal(c).muted, height: 1.4)),
        ],
      ]),
    );

Widget _section(BuildContext c, String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(t, style: label(pal(c).muted)),
    );

String speedLabel(double s) {
  final t = s.toStringAsFixed(2);
  return '${t.endsWith('0') ? t.substring(0, t.length - 1) : t}×'.replaceAll('.', ',');
}

// ------------------------------------------------------------ reproducir

Future<void> playOrAskVoice(BuildContext context) async {
  HapticFeedback.selectionClick();
  await ReaderEngine.I.toggle();
}

// ------------------------------------------------------------ voces

void showVoiceSheet(BuildContext context) {
  ReaderEngine.I.loadVoices();
  _sheet(context, tall: true, (c) => const _VoiceSheet());
}

class _VoiceSheet extends StatelessWidget {
  const _VoiceSheet();

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    return ListenableBuilder(
      listenable: Listenable.merge([Prefs.I, e]),
      builder: (context, _) {
        final pr = Prefs.I;
        final f = e.female, m = e.male;
        final needsBetter = (f != null && f.quality < 2) || (m != null && m.quality < 2);
        final fName = pr.latino ? 'Paulina' : 'Mónica';
        final mName = pr.latino ? 'Juan' : 'Jorge';
        final region = pr.latino ? 'Español (México)' : 'Español (España)';
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 32), children: [
          _title(context, 'Voces', sub: 'Elegí el acento, quién narra y cómo suenan los personajes.'),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Latino')),
                ButtonSegment(value: false, label: Text('España')),
              ],
              selected: {pr.latino},
              onSelectionChanged: (sel) {
                pr.setLatino(sel.first);
                e.voicesChanged(reload: true);
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _VoiceCard(
                voice: f,
                fallbackName: fName,
                role: pr.narratorMale ? 'Personajes' : 'Narra',
                selected: !pr.narratorMale,
                maleSlot: false,
                speed: pr.speedFemale,
                onSelect: () {
                  pr.setNarratorMale(false);
                  e.voicesChanged();
                },
                onSpeed: pr.setSpeedFemale,
                onSpeedEnd: (_) => e.voicesChanged(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _VoiceCard(
                voice: m,
                fallbackName: mName,
                role: pr.narratorMale ? 'Narra' : 'Personajes',
                selected: pr.narratorMale,
                maleSlot: true,
                speed: pr.speedMale,
                onSelect: () {
                  pr.setNarratorMale(true);
                  e.voicesChanged();
                },
                onSpeed: pr.setSpeedMale,
                onSpeedEnd: (_) => e.voicesChanged(),
              ),
            ),
          ]),
          if (needsBetter || f == null || m == null || Platform.isAndroid)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: p.accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Hacelas sonar mucho más naturales', style: TextStyle(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                Text(
                  Platform.isAndroid
                      ? 'En Android: Ajustes › Accesibilidad › Salida de texto a voz. Elegí «Servicios de voz de Google» como motor, '
                          'tocá el engranaje › Instalar datos de voz › ${pr.latino ? 'Español (Estados Unidos), que es el español latino' : 'Español (España)'}, '
                          'y descargá las voces. Después usá «Cambiar voz» para elegir una de mujer y una de hombre.'
                      : '${m == null ? 'Todavía no tenés una voz de hombre instalada. ' : ''}'
                          'En el iPhone: Ajustes › Accesibilidad › Leer y hablar (Read & Speak) › Voces › Español › $region. '
                          'Descargá «$fName (Mejorada)» y «$mName (Mejorada)», o «Premium» si aparece. '
                          'Si no lo encontrás, buscá «Voces» con la lupa de Ajustes. Después cerrá y abrí esta pantalla.',
                  style: const TextStyle(height: 1.45),
                ),
              ]),
            ),
          _section(context, 'DIÁLOGOS'),
          _DialogueOption(
            mode: DialogueMode.personajes,
            title: 'Voces por personaje',
            sub: 'Detecta si habla un hombre o una mujer («—dijo ella», «respondió el anciano») y usa la voz que corresponde.',
          ),
          _DialogueOption(
            mode: DialogueMode.otraVoz,
            title: 'La otra voz lee los diálogos',
            sub: 'Uno narra y el otro dice todo lo que hablan los personajes.',
          ),
          _DialogueOption(
            mode: DialogueMode.tono,
            title: 'Misma voz, otro tono',
            sub: 'Los diálogos se leen más pausados (con las voces mejoradas el cambio de tono es leve).',
          ),
          _DialogueOption(
            mode: DialogueMode.igual,
            title: 'Sin diferencia',
            sub: 'Todo con la voz del narrador, con una pausa al cambiar.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Interpretación', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Si el texto dice que alguien susurra, se escucha más bajo y lento; si grita, más rápido y firme.'),
            value: pr.expressive,
            onChanged: (v) {
              pr.setExpressive(v);
              e.voicesChanged();
            },
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: e.previewDialogue,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Escuchar un ejemplo con diálogos'),
            ),
          ),
          _section(context, 'PAUSAS ENTRE FRASES'),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Cortas')),
                ButtonSegment(value: 1, label: Text('Normales')),
                ButtonSegment(value: 2, label: Text('Largas')),
              ],
              selected: {pr.pauseLevel},
              onSelectionChanged: (s) {
                pr.setPauseLevel(s.first);
                e.voicesChanged();
              },
            ),
          ),
          const SizedBox(height: 8),
          Text('Las pausas largas ayudan a entender mejor y a seguir el texto.', style: TextStyle(color: p.muted, fontSize: 13)),
        ]);
      },
    );
  }
}

class _VoiceCard extends StatelessWidget {
  final NativeVoice? voice;
  final String fallbackName, role;
  final bool selected;
  final bool maleSlot;
  final double speed;
  final VoidCallback onSelect;
  final ValueChanged<double> onSpeed, onSpeedEnd;

  const _VoiceCard({
    required this.voice,
    required this.fallbackName,
    required this.role,
    required this.selected,
    required this.maleSlot,
    required this.speed,
    required this.onSelect,
    required this.onSpeed,
    required this.onSpeedEnd,
  });

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final v = voice;
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: BoxDecoration(
          color: selected ? p.hl : p.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? p.accent : Colors.transparent, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: selected ? p.accent : p.surface,
              child: Text(maleSlot ? 'H' : 'M',
                  style: TextStyle(fontWeight: FontWeight.w800, color: selected ? p.onAccent : p.fg)),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Escuchar',
              visualDensity: VisualDensity.compact,
              onPressed: v == null ? null : () => ReaderEngine.I.preview(v),
              icon: const Icon(Icons.play_circle_fill_rounded),
              color: p.accent,
            ),
          ]),
          const SizedBox(height: 8),
          Text(v == null ? fallbackName : voiceLabel(v),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(v == null ? 'No instalada' : '${regionOf(v.lang)} · ${v.qualityLabel}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Text(role, style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w800)),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => _pickVoice(context, maleSlot),
            child: const Text('Cambiar voz'),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.speed_rounded, size: 16, color: p.muted),
            const SizedBox(width: 4),
            Text(speedLabel(speed), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.fg)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
            child: Slider(
              value: speed.clamp(0.7, 1.3).toDouble(),
              min: 0.7,
              max: 1.3,
              divisions: 12,
              onChanged: onSpeed,
              onChangeEnd: onSpeedEnd,
            ),
          ),
        ]),
      ),
    );
  }
}

void _pickVoice(BuildContext context, bool maleSlot) {
  final e = ReaderEngine.I;
  _sheet(context, tall: true, (c) {
    final p = pal(c);
    return ListenableBuilder(
      listenable: Listenable.merge([e, Prefs.I]),
      builder: (c, _) {
        final cur = maleSlot ? e.male : e.female;
        final list = List<NativeVoice>.of(e.spanishVoices)..sort((a, b) => b.quality.compareTo(a.quality));
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28), children: [
          _title(c, maleSlot ? 'Voz de hombre' : 'Voz de mujer', sub: 'Tocá ▶ para escuchar y tocá la voz para elegirla.'),
          if (list.isEmpty) Text('No encontré voces en español instaladas.', style: TextStyle(color: p.muted)),
          for (final v in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(cur?.id == v.id ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: cur?.id == v.id ? p.accent : p.line),
              title: Text(voiceLabel(v), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${regionOf(v.lang)} · ${v.qualityLabel}'),
              trailing: IconButton(onPressed: () => e.preview(v), icon: const Icon(Icons.play_circle_outline_rounded)),
              onTap: () {
                Prefs.I.setVoiceFor(maleSlot, v.id);
                e.voicesChanged(reload: true);
              },
            ),
        ]);
      },
    );
  });
}

class _DialogueOption extends StatelessWidget {
  final DialogueMode mode;
  final String title, sub;
  const _DialogueOption({required this.mode, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final sel = Prefs.I.dialogueMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Prefs.I.setDialogueMode(mode);
        ReaderEngine.I.voicesChanged();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sel ? p.accent : p.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: p.muted, fontSize: 13, height: 1.35)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ velocidad

void showSpeedSheet(BuildContext context) {
  const presets = [0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5];
  _sheet(context, (c) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (c, _) {
        final s = Prefs.I.speed;
        final p = pal(c);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(c, 'Velocidad de lectura'),
          Row(children: [
            IconButton.filledTonal(
              onPressed: s <= 0.5 ? null : () => ReaderEngine.I.setSpeed(double.parse((s - 0.05).toStringAsFixed(2))),
              icon: const Icon(Icons.remove_rounded),
            ),
            Expanded(
              child: Center(
                child: Text(speedLabel(s), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: p.accent)),
              ),
            ),
            IconButton.filledTonal(
              onPressed: s >= 2.0 ? null : () => ReaderEngine.I.setSpeed(double.parse((s + 0.05).toStringAsFixed(2))),
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
          Slider(
            value: s.clamp(0.5, 2.0).toDouble(),
            min: 0.5,
            max: 2.0,
            divisions: 30,
            onChanged: (v) => Prefs.I.setSpeed(double.parse(v.toStringAsFixed(2))),
            onChangeEnd: (v) => ReaderEngine.I.setSpeed(double.parse(v.toStringAsFixed(2))),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in presets)
              ChoiceChip(
                label: Text(speedLabel(v)),
                selected: (s - v).abs() < 0.01,
                onSelected: (_) => ReaderEngine.I.setSpeed(v),
              ),
          ]),
          const SizedBox(height: 12),
          Text(
            'Para entender bien, entre 0,8× y 0,9×. Cada voz tiene además su propio ajuste en «Voces».',
            style: TextStyle(color: p.muted, height: 1.4),
          ),
        ]);
      },
    );
  });
}

// ------------------------------------------------------------ temporizador

void showSleepSheet(BuildContext context) {
  final e = ReaderEngine.I;
  _sheet(context, (c) {
    void pick(VoidCallback f) {
      f();
      Navigator.pop(c);
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(c, 'Temporizador', sub: 'La lectura se pausa sola, ideal para escuchar antes de dormir.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in [5, 10, 15, 30, 45, 60, 90]) ActionChip(label: Text('$m min'), onPressed: () => pick(() => e.setSleepMinutes(m))),
        ActionChip(
          avatar: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Al terminar el capítulo'),
          onPressed: () => pick(e.setSleepEndOfSection),
        ),
      ]),
      if (e.sleepActive) ...[
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: () => pick(e.clearSleep), icon: const Icon(Icons.close_rounded), label: const Text('Quitar temporizador')),
      ],
    ]);
  });
}

// ------------------------------------------------------------ traducción

void showTranslateSheet(BuildContext context) {
  _sheet(context, (c) => const _TranslateSheet());
}

class _TranslateSheet extends StatelessWidget {
  const _TranslateSheet();

  void _start() {
    final e = ReaderEngine.I;
    final m = e.meta!, c = e.content!;
    e.translation ??= List<String?>.filled(c.paras.length, null);
    if (!m.useTranslation) e.setUseTranslation(true);
    Translator.I.translateBook(m, c, e.translation!, e.idx, e.refresh);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final t = Translator.I;
    return ListenableBuilder(
      listenable: Listenable.merge([e, t]),
      builder: (context, _) {
        final m = e.meta;
        if (m == null) return const SizedBox.shrink();
        final running = t.running && t.bookId == m.id;
        final frac = m.paraCount == 0 ? 0.0 : m.translated / m.paraCount;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(context, 'Traducir al español',
              sub: 'Uso Google Traductor, así que necesita internet mientras traduce. Empieza por donde estás, '
                  'así podés escuchar mientras tanto. Lo traducido queda guardado.'),
          if (m.translated > 0 || running) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: frac, minHeight: 6, color: p.accent, backgroundColor: p.line),
            ),
            const SizedBox(height: 8),
            Text(
              running
                  ? 'Traduciendo ${fmtThousands(m.translated)} de ${fmtThousands(m.paraCount)} párrafos…'
                  : (m.fullyTranslated ? 'Traducción completa.' : 'Traducción en pausa: ${(frac * 100).round()} % lista.'),
              style: TextStyle(color: p.muted),
            ),
            if (t.error != null && t.bookId == m.id)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.error!, style: TextStyle(color: p.accent))),
            const SizedBox(height: 18),
            Text('LEER EN', style: label(p.muted)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Español')),
                  ButtonSegment(value: false, label: Text('Inglés original')),
                ],
                selected: {m.useTranslation},
                onSelectionChanged: (s) => e.setUseTranslation(s.first),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: running
                ? OutlinedButton.icon(onPressed: t.cancel, icon: const Icon(Icons.pause_rounded), label: const Text('Pausar traducción'))
                : (m.fullyTranslated
                    ? const SizedBox.shrink()
                    : FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.translate_rounded),
                        label: Text(m.translated == 0 ? 'Traducir el libro' : 'Seguir traduciendo'),
                      )),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------ apariencia

void showDisplaySheet(BuildContext context) {
  _sheet(context, tall: true, (c) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (c, _) {
        final pr = Prefs.I;
        final p = pal(c);
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28), children: [
          _title(c, 'Texto y tema'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
            child: Text(
              'Ella se acercó a la ventana y miró la lluvia. —¿Vamos a llegar a tiempo? —preguntó.',
              style: readingStyle(readingFonts[pr.readingFont], size: pr.fontSize, height: pr.lineHeight, color: p.fg),
            ),
          ),
          _section(c, 'TAMAÑO'),
          Row(children: [
            Text('A', style: serif(size: 15, color: p.fg)),
            Expanded(child: Slider(value: pr.fontSize, min: 14, max: 30, divisions: 16, onChanged: pr.setFontSize)),
            Text('A', style: serif(size: 28, color: p.fg)),
          ]),
          _section(c, 'INTERLINEADO'),
          Row(children: [
            Icon(Icons.density_small_rounded, color: p.muted),
            Expanded(child: Slider(value: pr.lineHeight, min: 1.4, max: 2.2, divisions: 8, onChanged: pr.setLineHeight)),
            Icon(Icons.density_large_rounded, color: p.muted),
          ]),
          _section(c, 'LETRA'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < readingFonts.length; i++)
              ChoiceChip(
                label: Text(readingFontNames[i], style: readingStyle(readingFonts[i], size: 15, height: 1.2, color: p.fg)),
                selected: pr.readingFont == i,
                onSelected: (_) => pr.setReadingFont(i),
              ),
          ]),
          _section(c, 'TEMA'),
          Row(children: [
            for (final t in AppTheme.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _ThemeSwatch(theme: t, selected: pr.theme == t, onTap: () => pr.setTheme(t)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo enfoque'),
            subtitle: const Text('Atenúa todo menos el párrafo que se está leyendo.'),
            value: pr.focusMode,
            onChanged: pr.setFocusMode,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Seguir el texto mientras escucho'),
            value: pr.followText,
            onChanged: pr.setFollowText,
          ),
        ]);
      },
    );
  });
}

class _ThemeSwatch extends StatelessWidget {
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final a = paletteFor(theme);
    final b = theme == AppTheme.auto ? nightPalette : a;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? p.accent : p.line, width: selected ? 2.5 : 1),
          gradient: LinearGradient(colors: [a.bg, a.bg, b.bg, b.bg], stops: const [0, .5, .5, 1]),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Aa', style: serif(size: 20, weight: FontWeight.w600, color: theme == AppTheme.auto ? a.accent : a.fg)),
          Text(themeNames[theme]!,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: theme == AppTheme.auto ? a.accent : a.muted)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ estadísticas

void showStatsSheet(BuildContext context) {
  _sheet(context, (c) => const _StatsSheet());
}

class _StatsSheet extends StatelessWidget {
  const _StatsSheet();

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListenableBuilder(
      listenable: Listenable.merge([Stats.I, Prefs.I]),
      builder: (context, _) {
        final st = Stats.I;
        final goal = Prefs.I.dailyGoal;
        final week = st.lastWeek;
        final maxV = week.fold<int>(goal, (a, b) => b > a ? b : a).toDouble();
        const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
        final now = DateTime.now();
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(context, 'Tu escucha'),
          Row(children: [
            _StatBox(value: '${st.todayMinutes}', unit: 'min hoy'),
            const SizedBox(width: 10),
            _StatBox(value: '${st.streak}', unit: st.streak == 1 ? 'día seguido' : 'días seguidos'),
            const SizedBox(width: 10),
            _StatBox(value: '${st.finishedBooks}', unit: st.finishedBooks == 1 ? 'libro terminado' : 'libros terminados'),
          ]),
          _section(context, 'ÚLTIMOS 7 DÍAS'),
          SizedBox(
            height: 140,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${week[i]}',
                          style: TextStyle(fontSize: 11, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(height: 4),
                      Container(
                        height: 4 + 96 * (maxV == 0 ? 0 : week[i] / maxV),
                        decoration: BoxDecoration(
                          color: week[i] >= goal ? p.accent : p.accent.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(days[now.subtract(Duration(days: 6 - i)).weekday - 1],
                          style: TextStyle(fontSize: 12, fontWeight: i == 6 ? FontWeight.w800 : FontWeight.w500, color: p.fg)),
                    ]),
                  ),
                ),
            ]),
          ),
          _section(context, 'META DIARIA'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in [10, 20, 30, 45, 60])
              ChoiceChip(label: Text('$g min'), selected: goal == g, onSelected: (_) => Prefs.I.setDailyGoal(g)),
          ]),
          const SizedBox(height: 12),
          Text('En total escuchaste ${fmtMinutes(st.totalMinutes)}.', style: TextStyle(color: p.muted)),
        ]);
      },
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value, unit;
  const _StatBox({required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.fg)),
          Text(unit, style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ notas

Future<void> showNoteDialog(BuildContext context, int para) async {
  final e = ReaderEngine.I;
  final ctrl = TextEditingController(text: e.meta?.notes['$para'] ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Nota'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Escribí lo que quieras recordar de esta parte'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Guardar')),
      ],
    ),
  );
  if (result != null) e.setNote(para, result);
}

// ------------------------------------------------------------ buscar

void showSearchSheet(BuildContext context, {required void Function(int) onPick}) {
  _sheet(context, tall: true, (c) => _SearchBody(onPick: (i) {
        Navigator.pop(c);
        onPick(i);
      }));
}

class _SearchBody extends StatefulWidget {
  final void Function(int) onPick;
  const _SearchBody({required this.onPick});
  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  List<(int, String)> _results = [];
  String _q = '';

  void _search(String q) {
    q = q.trim();
    final e = ReaderEngine.I;
    final out = <(int, String)>[];
    if (q.length >= 2) {
      final lq = q.toLowerCase();
      for (var i = 0; i < e.content!.paras.length && out.length < 200; i++) {
        final t = e.textAt(i);
        final at = t.toLowerCase().indexOf(lq);
        if (at < 0) continue;
        final s = (at - 50).clamp(0, t.length);
        final en = (at + q.length + 70).clamp(0, t.length);
        out.add((i, '${s > 0 ? '…' : ''}${t.substring(s, en)}${en < t.length ? '…' : ''}'));
      }
    }
    setState(() {
      _q = q;
      _results = out;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final c = ReaderEngine.I.content!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(children: [
        TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Buscar en el libro',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: p.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        if (_q.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _results.isEmpty ? 'Sin resultados para «$_q»' : '${_results.length}${_results.length == 200 ? '+' : ''} resultados',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: p.line),
            itemBuilder: (context, k) {
              final (i, snip) = _results[k];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(snip, style: serif(size: 15, height: 1.45, color: p.fg)),
                subtitle: Text(c.sections[c.sectionOf(i)].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => widget.onPick(i),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ marcadores y notas

void showBookmarksSheet(BuildContext context, {required void Function(int) onPick}) {
  final e = ReaderEngine.I;
  _sheet(context, tall: true, (c) {
    final p = pal(c);
    return ListenableBuilder(
      listenable: e,
      builder: (c, _) {
        final m = e.meta!;
        final marks = m.bookmarks;
        final content = e.content!;
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 24), children: [
          Row(children: [
            Expanded(child: _title(c, 'Marcadores y notas')),
            if (m.notes.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  final b = StringBuffer('${m.title}\n\n');
                  for (final i in marks) {
                    final n = m.notes['$i'];
                    if (n == null) continue;
                    b.writeln('• ${content.sections[content.sectionOf(i)].title}');
                    b.writeln('  «${e.textAt(i)}»');
                    b.writeln('  Nota: $n\n');
                  }
                  Clipboard.setData(ClipboardData(text: b.toString()));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notas copiadas')));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar notas'),
              ),
          ]),
          if (marks.isEmpty)
            Text('Mantené apretado un párrafo para agregar un marcador o una nota.', style: TextStyle(color: p.muted, height: 1.45)),
          for (final i in marks)
            Dismissible(
              key: ValueKey(i),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: p.hl,
                child: Icon(Icons.delete_outline_rounded, color: p.accent),
              ),
              onDismissed: (_) => e.toggleBookmark(i),
              child: InkWell(
                onTap: () {
                  Navigator.pop(c);
                  onPick(i);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(m.notes['$i'] != null ? Icons.sticky_note_2_rounded : Icons.bookmark_rounded, color: p.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(content.sections[content.sectionOf(i)].title,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text(e.textAt(i), maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(size: 15, color: p.fg)),
                        if (m.notes['$i'] != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(12)),
                            child: Text(m.notes['$i']!, style: const TextStyle(height: 1.35)),
                          ),
                        ],
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Editar nota',
                      onPressed: () => showNoteDialog(context, i),
                      icon: const Icon(Icons.edit_note_rounded),
                    ),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  });
}
