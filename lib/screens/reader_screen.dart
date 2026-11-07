import 'dart:ui' as ui;

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
import 'player_sheet.dart';
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
    final n = e.notice;
    if (n != null && mounted) {
      e.notice = null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n)));
    }
    if (e.idx != _lastIdx) {
      _lastIdx = e.idx;
      if (_follow && Prefs.I.followText) _scrollTo(e.idx);
    }
  }

  void _scrollTo(int i, {bool animate = true}) {
    if (!_items.isAttached) return;
    if (animate) {
      _items.scrollTo(index: i, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic, alignment: 0.2);
    } else {
      _items.jumpTo(index: i, alignment: 0.2);
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
      return Scaffold(appBar: AppBar(), body: Center(child: CircularProgressIndicator(color: p.accent)));
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
          builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.meta.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.fg)),
            Text(e.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.muted)),
          ]),
        ),
        actions: [
          if (widget.meta.isEnglish) const _TranslatePill(),
          IconButton(
            tooltip: 'Índice',
            icon: const Icon(Icons.toc_rounded),
            onPressed: () => _scaffold.currentState?.openDrawer(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) {
              if (v == 'search') showSearchSheet(context, onPick: (i) => _goTo(i));
              if (v == 'marks') showBookmarksSheet(context, onPick: (i) => _goTo(i));
              if (v == 'text') showDisplaySheet(context);
              if (v == 'voice') showVoiceSheet(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'search', child: ListTile(leading: Icon(Icons.search_rounded), title: Text('Buscar'))),
              PopupMenuItem(value: 'marks', child: ListTile(leading: Icon(Icons.bookmarks_outlined), title: Text('Marcadores'))),
              PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.text_fields_rounded), title: Text('Texto y tema'))),
              PopupMenuItem(value: 'voice', child: ListTile(leading: Icon(Icons.record_voice_over_outlined), title: Text('Voces'))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(children: [
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
              onLongPress: _paraMenu,
            ),
          ),
        ),
        if (!_follow)
          Positioned(
            bottom: 118 + MediaQuery.of(context).padding.bottom,
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
        Positioned(left: 0, right: 0, bottom: 0, child: _MiniPlayer(onExpand: () => showPlayerSheet(context))),
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
            leading: const Icon(Icons.edit_note_rounded),
            title: Text(e.meta!.notes['$i'] == null ? 'Agregar nota' : 'Editar nota'),
            onTap: () {
              Navigator.pop(c);
              showNoteDialog(context, i);
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
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      child: Text(e.content!.paras[i], style: serif(size: 17, height: 1.6, color: pal(context).fg)),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
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
    final style = readingStyle(readingFonts[prefs.readingFont], size: prefs.fontSize, height: prefs.lineHeight, color: p.fg);
    final marks = e.meta!.bookmarks.toSet();
    final notes = e.meta!.notes;
    final bottom = 140 + MediaQuery.of(context).padding.bottom;

    return ScrollablePositionedList.builder(
      itemScrollController: controller,
      itemCount: c.paras.length,
      padding: EdgeInsets.fromLTRB(0, 4, 0, bottom),
      itemBuilder: (context, i) {
        final text = e.textAt(i);
        final current = i == e.idx;
        Widget body;
        if (current) {
          body = ValueListenableBuilder<HL?>(
            valueListenable: e.hl,
            builder: (_, h, __) {
              if (h == null || h.para != i || h.end <= h.start || h.end > text.length) {
                return Text(text, style: style);
              }
              return Text.rich(TextSpan(style: style, children: [
                TextSpan(text: text.substring(0, h.start), style: TextStyle(color: p.fg.withValues(alpha: 0.55))),
                TextSpan(text: text.substring(h.start, h.end), style: TextStyle(backgroundColor: p.word, color: p.fg)),
                TextSpan(text: text.substring(h.end)),
              ]));
            },
          );
        } else {
          body = Text(text, style: style);
        }
        final heading = headings[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (heading != null && heading != 'Inicio')
              Padding(
                padding: EdgeInsets.fromLTRB(14, i == 0 ? 16 : 48, 14, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CAPÍTULO', style: label(p.accent)),
                  const SizedBox(height: 8),
                  Text(heading, style: serif(size: prefs.fontSize + 7, weight: FontWeight.w600, color: p.fg, height: 1.2)),
                ]),
              ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: prefs.focusMode && !current ? 0.28 : 1,
              child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(i),
              onLongPress: () => onLongPress(i),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: current ? p.accent : Colors.transparent, width: 3)),
                ),
                padding: const EdgeInsets.fromLTRB(11, 6, 14, 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: body),
                  if (marks.contains(i))
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 6),
                      child: Icon(notes['$i'] != null ? Icons.sticky_note_2_rounded : Icons.bookmark_rounded, size: 18, color: p.accent),
                    ),
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

// ------------------------------------------------------------ traducir

class _TranslatePill extends StatelessWidget {
  const _TranslatePill();

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
        String text;
        Widget? lead;
        if (running) {
          text = '${(m.translated * 100 / m.paraCount).round()} %';
          lead = SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.accent, value: m.translated / m.paraCount),
          );
        } else if (m.translated == 0) {
          text = 'Traducir';
        } else {
          text = m.useTranslation ? 'ES' : 'EN';
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: m.useTranslation || running ? p.hl : p.surface2,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => showTranslateSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  lead ?? Icon(Icons.translate_rounded, size: 16, color: p.accent),
                  const SizedBox(width: 6),
                  Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.fg)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ mini reproductor

class _MiniPlayer extends StatelessWidget {
  final VoidCallback onExpand;
  const _MiniPlayer({required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final bottom = MediaQuery.of(context).padding.bottom;
    return ListenableBuilder(
      listenable: Listenable.merge([e, Prefs.I]),
      builder: (context, _) {
        final c = e.content!;
        final m = e.meta!;
        final n = c.paras.length;
        final frac = n <= 1 ? 0.0 : e.idx / (n - 1);
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 10 + bottom),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: p.surface.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: p.line.withValues(alpha: 0.7)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  LinearProgressIndicator(value: frac, minHeight: 3, color: p.accent, backgroundColor: Colors.transparent),
                  InkWell(
                    onTap: onExpand,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(children: [
                        BookCover(meta: m, width: 40, radius: 6, shadow: false),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e.sectionTitle,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: p.fg)),
                            const SizedBox(height: 2),
                            Text(
                              '${(frac * 100).round()} % · faltan ${fmtMinutes(e.remainingMinutes)} · ${speedLabel(Prefs.I.speed)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ]),
                        ),
                        IconButton(onPressed: e.prevSentence, icon: const Icon(Icons.replay_rounded), tooltip: 'Frase anterior'),
                        _PlayButton(size: 50),
                        IconButton(onPressed: e.nextSentence, icon: const Icon(Icons.forward_rounded), tooltip: 'Frase siguiente'),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  final double size;
  const _PlayButton({required this.size});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: p.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => playOrAskVoice(context),
          child: Center(
            child: e.loading && e.playing
                ? SizedBox(width: size * 0.4, height: size * 0.4, child: CircularProgressIndicator(strokeWidth: 2.5, color: p.onAccent))
                : Icon(e.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: p.onAccent, size: size * 0.58),
          ),
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
              BookCover(meta: m, width: 60, radius: 8),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(size: 17, weight: FontWeight.w600, color: p.fg)),
                  if (m.author.isNotEmpty) Text(m.author, style: TextStyle(color: p.muted, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${c.sections.length} secciones', style: TextStyle(color: p.muted, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: p.line),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              itemCount: c.sections.length,
              itemBuilder: (context, i) {
                final s = c.sections[i];
                final done = i < cur;
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  selected: i == cur,
                  selectedTileColor: p.hl,
                  selectedColor: p.fg,
                  leading: Icon(
                    i == cur ? Icons.graphic_eq_rounded : (done ? Icons.check_circle_rounded : Icons.circle_outlined),
                    size: 20,
                    color: i == cur || done ? p.accent : p.line,
                  ),
                  title: Text(s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: done ? p.muted : p.fg, fontWeight: i == cur ? FontWeight.w800 : FontWeight.w500)),
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
