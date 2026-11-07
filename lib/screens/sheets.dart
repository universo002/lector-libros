import 'package:flutter/material.dart';

import '../prefs.dart';
import '../reader_engine.dart';
import '../theme.dart';
import '../translator.dart';

Future<void> _sheet(BuildContext context, WidgetBuilder builder, {bool tall = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => tall
        ? FractionallySizedBox(heightFactor: 0.88, child: builder(c))
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

// ------------------------------------------------------------ reproducir

Future<void> playOrAskVoice(BuildContext context) => ReaderEngine.I.toggle();

// ------------------------------------------------------------ voz

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
        final cur = e.currentVoice;
        final dv = e.dialogueVoice;
        final es = e.spanishVoices;
        final hasGood = es.any((v) => ReaderEngine.quality(v) != 'Estándar');
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28), children: [
          _title(context, 'Voz y lectura'),

          // Diálogos
          Text('DIÁLOGOS DE LOS PERSONAJES', style: label(p.muted)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<DialogueMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: DialogueMode.igual, label: Text('Igual')),
                ButtonSegment(value: DialogueMode.tono, label: Text('Otro tono')),
                ButtonSegment(value: DialogueMode.otraVoz, label: Text('Otra voz')),
              ],
              selected: {pr.dialogueMode},
              onSelectionChanged: (s) {
                pr.setDialogueMode(s.first);
                e.voicesChanged();
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (pr.dialogueMode) {
              DialogueMode.igual => 'Narración y diálogos con la misma voz, con una pausa al cambiar.',
              DialogueMode.tono => 'Lo que dicen los personajes se lee con un tono un poco más agudo y pausado, y con pausas antes y después.',
              DialogueMode.otraVoz => dv == null
                  ? 'Elegí abajo la voz de los diálogos (tocá «Diálogos» en una voz).'
                  : 'Los diálogos los lee ${dv['name']}.',
            },
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: e.previewDialogue,
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Escuchar un ejemplo'),
            ),
          ),
          const SizedBox(height: 14),

          // Pausas
          Text('PAUSAS ENTRE FRASES', style: label(p.muted)),
          const SizedBox(height: 8),
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
              onSelectionChanged: (s) => pr.setPauseLevel(s.first),
            ),
          ),
          const SizedBox(height: 22),

          // Voces
          Text('VOZ DEL NARRADOR', style: label(p.muted)),
          const SizedBox(height: 8),
          if (!hasGood)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                'Para que Mónica suene mucho más clara, descargá su versión mejorada: en el iPhone andá a '
                'Ajustes › Accesibilidad › Contenido leído › Voces › Español › España › Mónica, y bajá «Mónica (Mejorada)». '
                'Después volvé acá.',
                style: TextStyle(height: 1.45),
              ),
            ),
          for (final v in es)
            _VoiceTile(
              v: v,
              selected: cur != null && cur['name'] == v['name'] && cur['locale'] == v['locale'],
              dialogue: pr.dialogueMode == DialogueMode.otraVoz && dv != null && dv['name'] == v['name'] && dv['locale'] == v['locale'],
            ),
          if (es.isEmpty) Text('No encontré voces en español en este iPhone.', style: TextStyle(color: p.muted)),
        ]);
      },
    );
  }
}

class _VoiceTile extends StatelessWidget {
  final Map<String, String> v;
  final bool selected, dialogue;
  const _VoiceTile({required this.v, required this.selected, required this.dialogue});

  String _region(String l) {
    final x = l.toLowerCase().replaceAll('_', '-');
    if (x == 'es-es') return 'España';
    if (x == 'es-mx') return 'México';
    if (x == 'es-ar') return 'Argentina';
    if (x == 'es-us') return 'EE. UU.';
    if (x == 'es-co') return 'Colombia';
    if (x == 'es-cl') return 'Chile';
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final q = ReaderEngine.quality(v);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Prefs.I.setVoice(v['name']!, v['locale']!);
        e.voicesChanged();
        e.preview(v);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: selected ? p.accent : p.surface2,
            child: Text((v['name'] ?? '?').substring(0, 1),
                style: TextStyle(fontWeight: FontWeight.w800, color: selected ? p.onAccent : p.fg)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(v['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (selected) const _Badge('Narrador'),
                if (dialogue) const _Badge('Diálogos'),
              ]),
              Text('${_region(v['locale'] ?? '')} · $q', style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          ),
          if (Prefs.I.dialogueMode == DialogueMode.otraVoz)
            TextButton(
              onPressed: () {
                Prefs.I.setDialogueVoice(v['name']!, v['locale']!);
                e.voicesChanged();
                e.preview(v, dialogue: true);
              },
              child: const Text('Diálogos'),
            ),
          IconButton(tooltip: 'Escuchar', onPressed: () => e.preview(v), icon: const Icon(Icons.play_circle_outline_rounded)),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
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

// ------------------------------------------------------------ velocidad

void showSpeedSheet(BuildContext context) {
  const presets = [0.7, 0.8, 0.9, 1.0, 1.1, 1.25];
  _sheet(context, (c) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (c, _) {
        final s = Prefs.I.speed;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(c, 'Velocidad'),
          Text('${s.toStringAsFixed(2)}×', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: pal(c).accent)),
          Slider(
            value: s.clamp(0.6, 1.8).toDouble(),
            min: 0.6,
            max: 1.8,
            divisions: 24,
            onChanged: (v) => Prefs.I.setSpeed(double.parse(v.toStringAsFixed(2))),
            onChangeEnd: (v) => ReaderEngine.I.setSpeed(double.parse(v.toStringAsFixed(2))),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in presets)
              ChoiceChip(
                label: Text('$v×'),
                selected: (s - v).abs() < 0.01,
                onSelected: (_) => ReaderEngine.I.setSpeed(v),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Para entender mejor, probá entre 0,8× y 0,9×. Para repasar algo que ya conocés, 1,1× o más.', style: TextStyle(color: pal(c).muted, height: 1.4)),
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
      _title(c, 'Temporizador', sub: 'La lectura se pausa sola.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in [10, 15, 30, 45, 60, 90]) ActionChip(label: Text('$m min'), onPressed: () => pick(() => e.setSleepMinutes(m))),
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

// ------------------------------------------------------------ apariencia

void showDisplaySheet(BuildContext context) {
  _sheet(context, (c) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (c, _) {
        final pr = Prefs.I;
        final p = pal(c);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(c, 'Texto y tema'),
          Row(children: [
            Text('A', style: serif(size: 15, color: p.fg)),
            Expanded(child: Slider(value: pr.fontSize, min: 14, max: 30, divisions: 16, onChanged: pr.setFontSize)),
            Text('A', style: serif(size: 28, color: p.fg)),
          ]),
          const SizedBox(height: 8),
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
          Text(themeNames[theme]!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: theme == AppTheme.auto ? a.accent : a.muted)),
        ]),
      ),
    );
  }
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

// ------------------------------------------------------------ marcadores

void showBookmarksSheet(BuildContext context, {required void Function(int) onPick}) {
  final e = ReaderEngine.I;
  _sheet(context, tall: true, (c) {
    final p = pal(c);
    return ListenableBuilder(
      listenable: e,
      builder: (c, _) {
        final marks = e.meta!.bookmarks;
        final content = e.content!;
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 24), children: [
          _title(c, 'Marcadores'),
          if (marks.isEmpty)
            Text('Mantené apretado un párrafo y elegí «Agregar marcador» para guardarlo acá.', style: TextStyle(color: p.muted, height: 1.45)),
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
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bookmark_rounded, color: p.accent),
                title: Text(e.textAt(i), maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(size: 15, color: p.fg)),
                subtitle: Text(content.sections[content.sectionOf(i)].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(c);
                  onPick(i);
                },
              ),
            ),
        ]);
      },
    );
  });
}
