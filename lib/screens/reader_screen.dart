import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models.dart';
import '../prefs.dart';
import '../reader_engine.dart';
import '../theme.dart';
import '../translator.dart';
import '../widgets/book_cover.dart';
import 'sheets.dart';

class ReaderScreen extends StatefulWidget {
  final BookMeta meta;
  const ReaderScreen({super.key, required this.meta});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _items = ItemScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _loading = true;
  bool _follow = true;
  int _lastIdx = -1;

  ReaderEngine get e => ReaderEngine.I;

  @override
  void initState() {
    super.initState();
    e.addListener(_onEngine);
    _load();
  }

  Future<void> _load() async {
    await e.open(widget.meta);
    if (!mounted) return;
    setState(() => _loading = false);
    _lastIdx = e.idx;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(e.idx, animate: false));
  }

  @override
  void dispose() {
    e.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    if (e.meta?.id != widget.meta.id) return;
    if (e.idx != _lastIdx) {
      _lastIdx = e.idx;
      if (_follow) _scrollTo(e.idx);
    }
  }

  void _scrollTo(int i, {bool animate = true}) {
    if (!_items.isAttached) return;
    if (animate) {
      _items.scrollTo(index: i, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic, alignment: 0.22);
    } else {
      _items.jumpTo(index: i, alignment: 0.22);
    }
  }

  void _goTo(int i, {bool? play}) {
    setState(() => _follow = true);
    e.jumpTo(i, play: play);
    _scrollTo(i);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (_loading || e.content == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      key: _scaffold,
      drawer: _TocDrawer(onPick: (i) {
        Navigator.pop(context);
        _goTo(i);
      }),
      appBar: AppBar(
        titleSpacing: 0,
        title: ListenableBuilder(
          listenable: e,
          builder: (context, _) {
            final c = e.content!;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(size: 16, weight: FontWeight.w600, color: p.fg)),
              Text(c.sections[c.sectionOf(e.idx)].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.muted)),
            ]);
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Índice',
            icon: const Icon(Icons.format_list_bulleted_rounded),
            onPressed: () => _scaffold.currentState?.openDrawer(),
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => showSearchSheet(context, onPick: (i) => _goTo(i)),
          ),
          IconButton(
            tooltip: 'Marcadores',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => showBookmarksSheet(context, onPick: (i) => _goTo(i)),
          ),
          IconButton(
            tooltip: 'Texto y tema',
            icon: const Icon(Icons.text_fields_rounded),
            onPressed: () => showDisplaySheet(context),
          ),
        ],
      ),
      body: Column(children: [
        if (widget.meta.isEnglish) const _TranslationBar(),
        Expanded(
          child: Stack(children: [
            NotificationListener<UserScrollNotification>(
              onNotification: (n) {
                if (n.direction != ScrollDirection.idle && _follow) setState(() => _follow = false);
                return false;
              },
              child: ListenableBuilder(
                listenable: Listenable.merge([e, Prefs.I]),
                builder: (context, _) => _TextList(
                  controller: _items,
                  onTap: (i) => _goTo(i, play: true),
                  onLongPress: (i) => _paraMenu(i),
                ),
              ),
            ),
            if (!_follow)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() => _follow = true);
                      _scrollTo(e.idx);
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text('Volver a la lectura'),
                  ),
                ),
              ),
          ]),
        ),
        _PlayerPanel(onSeek: (i) => _goTo(i)),
      ]),
    );
  }

  void _paraMenu(int i) {
    final marked = e.meta!.bookmarks.contains(i);
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: const Text('Escuchar desde acá'),
            onTap: () {
              Navigator.pop(c);
              _goTo(i, play: true);
            },
          ),
          ListTile(
            leading: Icon(marked ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
            title: Text(marked ? 'Quitar marcador' : 'Agregar marcador'),
            onTap: () {
              Navigator.pop(c);
              e.toggleBookmark(i);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copiar párrafo'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: e.textAt(i)));
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Párrafo copiado')));
            },
          ),
          if (widget.meta.isEnglish && widget.meta.useTranslation)
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Ver el original en inglés'),
              onTap: () {
                Navigator.pop(c);
                showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Text(e.content!.paras[i], style: serif(size: 17, height: 1.6, color: pal(context).fg)),
                    ),
                  ),
                );
              },
            ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ texto

class _TextList extends StatelessWidget {
  final ItemScrollController controller;
  final void Function(int) onTap, onLongPress;
  const _TextList({required this.controller, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final e = ReaderEngine.I;
    final c = e.content!;
    final p = pal(context);
    final prefs = Prefs.I;
    final headings = {for (final s in c.sections) s.start: s.title};
    final style = serif(size: prefs.fontSize, height: 1.65, color: p.fg);
    final marks = e.meta!.bookmarks.toSet();

    return ScrollablePositionedList.builder(
      itemScrollController: controller,
      itemCount: c.paras.length,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
      itemBuilder: (context, i) {
        final text = e.textAt(i);
        final current = i == e.idx;
        Widget body = Text(text, style: style);
        if (current && prefs.wordHighlight) {
          body = ValueListenableBuilder<WordRange?>(
            valueListenable: e.word,
            builder: (_, w, __) {
              if (w == null || w.para != i || w.end <= w.start || w.end > text.length) return Text(text, style: style);
              return Text.rich(TextSpan(style: style, children: [
                TextSpan(text: text.substring(0, w.start)),
                TextSpan(text: text.substring(w.start, w.end), style: TextStyle(backgroundColor: p.word)),
                TextSpan(text: text.substring(w.end), style: TextStyle(color: p.fg.withValues(alpha: 0.78))),
              ]));
            },
          );
        }
        final heading = headings[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (heading != null && heading != 'Inicio')
              Padding(
                padding: EdgeInsets.fromLTRB(12, i == 0 ? 12 : 40, 12, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 28, height: 3, color: p.accent),
                  const SizedBox(height: 12),
                  Text(heading, style: serif(size: prefs.fontSize + 5, weight: FontWeight.w600, color: p.fg, height: 1.25)),
                ]),
              ),
            Material(
              color: current ? p.highlight : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(i),
                onLongPress: () => onLongPress(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: body),
                    if (marks.contains(i))
                      Padding(padding: const EdgeInsets.only(left: 6, top: 4), child: Icon(Icons.bookmark_rounded, size: 18, color: p.accent)),
                  ]),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------ traducción

class _TranslationBar extends StatelessWidget {
  const _TranslationBar();

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
        final m = e.meta!;
        final running = t.running && t.bookId == m.id;
        final hasSome = m.translated > 0 || running;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
          child: !hasSome
              ? Row(children: [
                  Icon(Icons.translate_rounded, color: p.accent),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Este libro está en inglés', style: TextStyle(fontWeight: FontWeight.w600))),
                  FilledButton(onPressed: _start, child: const Text('Traducir')),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: false, label: Text('Inglés')),
                          ButtonSegment(value: true, label: Text('Español')),
                        ],
                        selected: {m.useTranslation},
                        onSelectionChanged: (s) => e.setUseTranslation(s.first),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (running)
                      IconButton(tooltip: 'Pausar traducción', onPressed: t.cancel, icon: const Icon(Icons.pause_circle_outline_rounded))
                    else if (!m.fullyTranslated)
                      IconButton(tooltip: 'Seguir traduciendo', onPressed: _start, icon: const Icon(Icons.play_circle_outline_rounded)),
                  ]),
                  if (running || !m.fullyTranslated) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: running && t.total > 0 ? t.done / t.total : m.translated / m.paraCount,
                        minHeight: 4,
                        backgroundColor: p.line,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      running
                          ? (t.status.startsWith('Traduciendo')
                              ? 'Traduciendo ${fmtThousands(t.done)} de ${fmtThousands(t.total)} párrafos. Ya podés escuchar mientras tanto.'
                              : t.status)
                          : 'Traducción en pausa: ${(m.translated * 100 / m.paraCount).round()} % lista.',
                      style: TextStyle(fontSize: 12.5, color: p.muted),
                    ),
                  ],
                ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------ reproductor

class _PlayerPanel extends StatefulWidget {
  final void Function(int) onSeek;
  const _PlayerPanel({required this.onSeek});
  @override
  State<_PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<_PlayerPanel> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    return ListenableBuilder(
      listenable: Listenable.merge([e, Prefs.I]),
      builder: (context, _) {
        final c = e.content!;
        final n = c.paras.length;
        final shown = (_drag ?? e.idx.toDouble()).clamp(0, (n - 1).toDouble()).toDouble();
        final pct = n <= 1 ? 0 : (shown / (n - 1) * 100).round();
        final dragSection = c.sections[c.sectionOf(shown.round())].title;
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  SizedBox(width: 44, child: Text('$pct %', style: TextStyle(fontSize: 12, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
                  Expanded(
                    child: Slider(
                      value: shown,
                      min: 0,
                      max: (n - 1).clamp(1, 1 << 30).toDouble(),
                      onChanged: (v) => setState(() => _drag = v),
                      onChangeEnd: (v) {
                        setState(() => _drag = null);
                        widget.onSeek(v.round());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text('−${fmtMinutes(e.remainingMinutes)}',
                        textAlign: TextAlign.right, maxLines: 1, style: TextStyle(fontSize: 12, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ]),
                Text(
                  _drag != null ? dragSection : 'Este capítulo: faltan ${fmtMinutes(e.sectionRemainingMinutes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.muted),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _Pill(
                    label: '${Prefs.I.speed.toStringAsFixed(Prefs.I.speed == Prefs.I.speed.roundToDouble() ? 0 : 2).replaceAll(RegExp(r'0$'), '')}×',
                    onTap: () => showSpeedSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Párrafo anterior (mantené para el capítulo)',
                    iconSize: 32,
                    onPressed: e.prev,
                    icon: GestureDetector(onLongPress: () => e.skipSection(-1), child: const Icon(Icons.fast_rewind_rounded)),
                  ),
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: FilledButton(
                      style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                      onPressed: e.toggle,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                        child: Icon(e.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(e.playing), size: 38),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Párrafo siguiente (mantené para el capítulo)',
                    iconSize: 32,
                    onPressed: e.next,
                    icon: GestureDetector(onLongPress: () => e.skipSection(1), child: const Icon(Icons.fast_forward_rounded)),
                  ),
                  _Pill(
                    icon: e.sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                    label: e.sleepAt != null
                        ? '${e.sleepAt!.difference(DateTime.now()).inMinutes + 1}′'
                        : (e.sleepEndOfSection ? 'Cap.' : ''),
                    active: e.sleepActive,
                    onTap: () => showSleepSheet(context),
                  ),
                ]),
                TextButton.icon(
                  onPressed: () => showVoiceSheet(context),
                  icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                  label: Text(e.currentVoice?['name'] ?? 'Elegir voz', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;
  const _Pill({required this.label, this.icon, this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Material(
      color: active ? p.highlight : p.bg,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) Icon(icon, size: 20, color: active ? p.accent : p.fg),
            if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
            if (label.isNotEmpty) Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: active ? p.accent : p.fg)),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ índice

class _TocDrawer extends StatelessWidget {
  final void Function(int) onPick;
  const _TocDrawer({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final m = e.meta!, c = e.content!;
    final cur = c.sectionOf(e.idx);
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              BookCover(meta: m, width: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(size: 17, weight: FontWeight.w600, color: p.fg)),
                  if (m.author.isNotEmpty) Text(m.author, style: TextStyle(color: p.muted, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: p.line),
          Expanded(
            child: ListView.builder(
              itemCount: c.sections.length,
              itemBuilder: (context, i) {
                final s = c.sections[i];
                final done = i < cur;
                return ListTile(
                  selected: i == cur,
                  selectedTileColor: p.highlight,
                  leading: Icon(
                    i == cur ? Icons.graphic_eq_rounded : (done ? Icons.check_circle_rounded : Icons.circle_outlined),
                    size: 20,
                    color: i == cur || done ? p.accent : p.line,
                  ),
                  title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: done ? p.muted : p.fg)),
                  onTap: () => onPick(s.start),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
