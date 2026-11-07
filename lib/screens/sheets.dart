import 'package:flutter/material.dart';

import '../prefs.dart';
import '../reader_engine.dart';
import '../theme.dart';
import '../translator.dart';
import '../voices.dart';

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

// ------------------------------------------------------------ reproducir (o pedir voz)

/// Si todavía no hay ninguna voz natural descargada, ofrece descargar una.
Future<void> playOrAskVoice(BuildContext context) async {
  final e = ReaderEngine.I;
  if (e.playing) {
    await e.pause();
    return;
  }
  final needs = !Prefs.I.useSystemVoice && !Voices.I.isReady(e.narratorVoice);
  if (!needs) {
    await e.play();
    return;
  }
  await _sheet(context, (c) => const _VoiceOnboarding());
  if (Voices.I.isReady(e.narratorVoice) || Prefs.I.useSystemVoice) {
    await e.voicesChanged();
    await e.play();
  }
}

class _VoiceOnboarding extends StatefulWidget {
  const _VoiceOnboarding();
  @override
  State<_VoiceOnboarding> createState() => _VoiceOnboardingState();
}

class _VoiceOnboardingState extends State<_VoiceOnboarding> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    final e = ReaderEngine.I;
    final narr = e.narratorVoice ?? voiceById('daniela')!;
    final ok = await Voices.I.download(narr);
    if (ok && !e.readingEnglish && Prefs.I.dialogueVoice) {
      final d = voiceById(Prefs.I.dialogue);
      if (d != null) await Voices.I.download(d);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final narr = e.narratorVoice ?? voiceById('daniela')!;
    final dia = (!e.readingEnglish && Prefs.I.dialogueVoice) ? voiceById(Prefs.I.dialogue) : null;
    final mb = narr.approxMb + (dia != null && dia.dir != narr.dir ? dia.approxMb : 0);
    return ListenableBuilder(
      listenable: Voices.I,
      builder: (context, _) {
        final downloading = Voices.I.isDownloading(narr) || (dia != null && Voices.I.isDownloading(dia));
        final prog = Voices.I.progress[narr.dir] ?? (dia != null ? Voices.I.progress[dia.dir] : null);
        final err = Voices.I.errors[narr.dir] ?? (dia != null ? Voices.I.errors[dia.dir] : null);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.graphic_eq_rounded, color: p.accent, size: 30),
          ),
          const SizedBox(height: 16),
          _title(context, 'Descargá una voz natural',
              sub: 'Las voces naturales suenan mucho más humanas que las del iPhone y funcionan sin internet. '
                  'Se descargan una sola vez.'),
          _VoiceRow(v: narr, role: 'Narrador'),
          if (dia != null && dia.id != narr.id) _VoiceRow(v: dia, role: 'Diálogos'),
          const SizedBox(height: 14),
          if (downloading || _busy) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: prog == null || prog < 0 ? null : prog,
                minHeight: 6,
                color: p.accent,
                backgroundColor: p.line,
              ),
            ),
            const SizedBox(height: 8),
            Text(prog != null && prog < 0 ? 'Instalando la voz…' : 'Descargando… podés dejar la pantalla abierta.',
                style: TextStyle(color: p.muted)),
          ] else ...[
            if (err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(err, style: TextStyle(color: p.accent))),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download_rounded),
                label: Text('Descargar y escuchar (≈ $mb MB)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Prefs.I.setUseSystemVoice(true);
                  Navigator.pop(context);
                },
                child: const Text('Usar la voz del iPhone por ahora'),
              ),
            ),
          ],
        ]);
      },
    );
  }
}

class _VoiceRow extends StatelessWidget {
  final VoiceInfo v;
  final String role;
  const _VoiceRow({required this.v, required this.role});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: p.surface2,
          child: Text(v.name.substring(0, 1), style: TextStyle(fontWeight: FontWeight.w800, color: p.fg)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${v.name} · ${v.region}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(v.description, style: TextStyle(color: p.muted, fontSize: 13)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(20)),
          child: Text(role, style: TextStyle(color: p.accent, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ voces

void showVoiceSheet(BuildContext context) {
  ReaderEngine.I.loadSystemVoices();
  _sheet(context, tall: true, (c) => const _VoiceSheet());
}

class _VoiceSheet extends StatelessWidget {
  const _VoiceSheet();

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    return ListenableBuilder(
      listenable: Listenable.merge([Voices.I, Prefs.I, e]),
      builder: (context, _) {
        final sys = Prefs.I.useSystemVoice;
        final spanish = voiceCatalog.where((v) => v.lang == 'es').toList();
        final english = voiceCatalog.where((v) => v.lang == 'en').toList();
        return ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 28), children: [
          _title(context, 'Voces'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Naturales'), icon: Icon(Icons.auto_awesome_rounded, size: 18)),
              ButtonSegment(value: true, label: Text('Del iPhone'), icon: Icon(Icons.phone_iphone_rounded, size: 18)),
            ],
            selected: {sys},
            onSelectionChanged: (s) {
              Prefs.I.setUseSystemVoice(s.first);
              e.voicesChanged();
            },
          ),
          const SizedBox(height: 18),
          if (!sys) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: [
                  Icon(Icons.forum_outlined, color: p.accent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Otra voz para los diálogos', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Switch(
                    value: Prefs.I.dialogueVoice,
                    onChanged: (v) {
                      Prefs.I.setDialogueVoice(v);
                      e.voicesChanged();
                    },
                  ),
                ]),
                Text(
                  'Lo que dicen los personajes (entre rayas o comillas) se lee con la voz de «Diálogos», y la narración con la del «Narrador».',
                  style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Text('ESPAÑOL', style: label(p.muted)),
            const SizedBox(height: 6),
            for (final v in spanish) _VoiceTile(v: v),
            const SizedBox(height: 18),
            Text('INGLÉS (LIBROS SIN TRADUCIR)', style: label(p.muted)),
            const SizedBox(height: 6),
            for (final v in english) _VoiceTile(v: v),
            const SizedBox(height: 12),
            Text('Las voces se guardan en el celular y funcionan sin internet. Mantené apretada una voz descargada para borrarla.',
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                'Para que suenen un poco mejor: en el iPhone andá a Ajustes › Accesibilidad › Contenido leído › Voces › Español, '
                'y descargá una voz que diga «Mejorada» o «Premium».',
                style: TextStyle(height: 1.45),
              ),
            ),
            const SizedBox(height: 10),
            for (final v in e.sysVoices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(v['name'] ?? ''),
                subtitle: Text(v['locale'] ?? ''),
                trailing: e.currentSystemVoice?['name'] == v['name'] && e.currentSystemVoice?['locale'] == v['locale']
                    ? Icon(Icons.check_circle_rounded, color: p.accent)
                    : const Icon(Icons.play_circle_outline_rounded),
                onTap: () => e.setSystemVoice(v),
              ),
          ],
        ]);
      },
    );
  }
}

class _VoiceTile extends StatelessWidget {
  final VoiceInfo v;
  const _VoiceTile({required this.v});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final ready = Voices.I.isReady(v);
    final prog = Voices.I.progress[v.dir];
    final err = Voices.I.errors[v.dir];
    final isNarr = v.lang == 'es' ? Prefs.I.narrator == v.id : Prefs.I.english == v.id;
    final isDia = v.lang == 'es' && Prefs.I.dialogue == v.id && Prefs.I.dialogueVoice;

    Widget trailing;
    if (prog != null) {
      trailing = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3, value: prog < 0 ? null : prog, color: p.accent),
      );
    } else if (!ready) {
      trailing = OutlinedButton(
        onPressed: () => Voices.I.download(v),
        child: Text('${v.approxMb} MB'),
      );
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Escuchar', onPressed: () => e.previewVoice(v), icon: const Icon(Icons.play_circle_outline_rounded)),
        PopupMenuButton<String>(
          tooltip: 'Usar',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (s) {
            if (s == 'narr') {
              if (v.lang == 'es') {
                Prefs.I.setNarrator(v.id);
              } else {
                Prefs.I.setEnglish(v.id);
              }
            }
            if (s == 'dia') {
              Prefs.I.setDialogue(v.id);
              Prefs.I.setDialogueVoice(true);
            }
            if (s == 'del') Voices.I.remove(v);
            e.voicesChanged();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'narr', child: Text(v.lang == 'es' ? 'Usar como narrador' : 'Usar para inglés')),
            if (v.lang == 'es') const PopupMenuItem(value: 'dia', child: Text('Usar para diálogos')),
            const PopupMenuItem(value: 'del', child: Text('Borrar del celular')),
          ],
        ),
      ]);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onLongPress: ready ? () => Voices.I.remove(v) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: isNarr || isDia ? p.accent : p.surface2,
            child: Text(v.name.substring(0, 1),
                style: TextStyle(fontWeight: FontWeight.w800, color: isNarr || isDia ? p.onAccent : p.fg)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(v.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (isNarr) _Badge(v.lang == 'es' ? 'Narrador' : 'Inglés'),
                if (isDia) const _Badge('Diálogos'),
              ]),
              Text('${v.region} · ${v.quality}', style: TextStyle(color: p.muted, fontSize: 13)),
              if (err != null) Text(err, style: TextStyle(color: p.accent, fontSize: 12.5)),
            ]),
          ),
          trailing,
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
  const presets = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5];
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
          Text('Con las voces naturales, la velocidad cambia sin distorsionar la voz.', style: TextStyle(color: pal(c).muted)),
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
