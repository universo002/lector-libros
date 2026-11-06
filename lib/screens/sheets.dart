import 'package:flutter/material.dart';

import '../prefs.dart';
import '../reader_engine.dart';
import '../theme.dart';

Future<void> _sheet(BuildContext context, WidgetBuilder builder, {bool tall = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: tall,
    useSafeArea: true,
    builder: (c) => tall
        ? FractionallySizedBox(heightFactor: 0.85, child: builder(c))
        : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: builder(c))),
  );
}

Widget _title(BuildContext c, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(t, style: serif(size: 20, weight: FontWeight.w600, color: pal(c).fg)),
    );

// ------------------------------------------------------------ velocidad

void showSpeedSheet(BuildContext context) {
  const presets = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  _sheet(context, (c) {
    return ListenableBuilder(
      listenable: Prefs.I,
      builder: (c, _) {
        final s = Prefs.I.speed;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(c, 'Velocidad de lectura'),
          Text('${s.toStringAsFixed(2)}×', style: serif(size: 34, weight: FontWeight.w600, color: pal(c).accent)),
          Slider(
            value: s,
            min: 0.5,
            max: 2.0,
            divisions: 30,
            onChanged: (v) => Prefs.I.setSpeed(double.parse(v.toStringAsFixed(2))),
            onChangeEnd: (v) => ReaderEngine.I.setSpeed(double.parse(v.toStringAsFixed(2))),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in presets)
              ChoiceChip(
                label: Text('$v×'.replaceAll('.0×', '×')),
                selected: (s - v).abs() < 0.01,
                onSelected: (_) => ReaderEngine.I.setSpeed(v),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Para estudiar suele funcionar bien entre 1,2× y 1,4×.', style: TextStyle(color: pal(c).muted)),
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
      _title(c, 'Apagar la lectura'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in [5, 15, 30, 45, 60, 90]) ActionChip(label: Text('$m min'), onPressed: () => pick(() => e.setSleepMinutes(m))),
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

// ------------------------------------------------------------ voces

void showVoiceSheet(BuildContext context) {
  final e = ReaderEngine.I;
  e.loadVoices();
  _sheet(context, tall: true, (c) {
    final p = pal(c);
    return ListenableBuilder(
      listenable: e,
      builder: (c, _) {
        final cur = e.currentVoice;
        String quality(Map<String, String> v) {
          final q = (v['quality'] ?? '').toLowerCase();
          if (q.contains('premium')) return 'Premium';
          if (q.contains('enhanced')) return 'Mejorada';
          return 'Estándar';
        }

        String region(String l) {
          final x = l.toLowerCase().replaceAll('_', '-');
          if (x == 'es-es') return 'España';
          if (x == 'es-mx') return 'México';
          if (x == 'es-ar') return 'Argentina';
          if (x == 'es-us') return 'Estados Unidos';
          if (x == 'es-co') return 'Colombia';
          return l;
        }

        return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          _title(c, 'Voz'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.highlight, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome_rounded, color: p.accent, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Para una voz más humana', style: TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              const Text(
                'En el iPhone andá a Ajustes › Accesibilidad › Contenido leído › Voces › Español › España, '
                'y descargá una voz que diga «Mejorada» o «Premium». Después volvé acá: aparece arriba de todo.',
                style: TextStyle(height: 1.45),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (e.voices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No encontré voces en español instaladas.', style: TextStyle(color: p.muted)),
            ),
          for (final v in e.voices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(v['name'] ?? ''),
              subtitle: Text('${region(v['locale'] ?? '')} · ${quality(v)}'),
              leading: Icon(
                quality(v) == 'Estándar' ? Icons.record_voice_over_outlined : Icons.workspace_premium_rounded,
                color: quality(v) == 'Estándar' ? p.muted : p.accent,
              ),
              trailing: cur != null && cur['name'] == v['name'] && cur['locale'] == v['locale']
                  ? Icon(Icons.check_circle_rounded, color: p.accent)
                  : const Icon(Icons.play_circle_outline_rounded),
              onTap: () => e.setVoice(v),
            ),
        ]);
      },
    );
  });
}

// ------------------------------------------------------------ texto y tema

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
            Text('A', style: serif(size: 14, color: p.fg)),
            Expanded(child: Slider(value: pr.fontSize, min: 14, max: 30, divisions: 16, onChanged: pr.setFontSize)),
            Text('A', style: serif(size: 26, color: p.fg)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final t in ReadingTheme.values)
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
            title: const Text('Resaltar la palabra que se lee'),
            value: pr.wordHighlight,
            onChanged: pr.setWordHighlight,
          ),
        ]);
      },
    );
  });
}

class _ThemeSwatch extends StatelessWidget {
  final ReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sw = paletteFor(theme);
    final p = pal(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: sw.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? p.accent : p.line, width: selected ? 2.5 : 1),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Aa', style: serif(size: 20, weight: FontWeight.w600, color: sw.fg)),
          Text(themeNames[theme]!, style: TextStyle(fontSize: 12, color: sw.muted)),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Buscar en el libro',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: p.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
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
        return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
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
                color: p.highlight,
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
