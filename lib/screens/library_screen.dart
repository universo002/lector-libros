import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../covers.dart';
import '../importer.dart';
import '../library.dart';
import '../models.dart';
import '../reader_engine.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import 'reader_screen.dart';
import 'sheets.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  double? _progress;
  String _label = '';
  String? _importName;
  String? _error;

  Future<void> _add() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'epub', 'txt']);
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() {
      _importName = res!.files.single.name;
      _progress = 0;
      _label = 'Abriendo…';
      _error = null;
    });
    try {
      final r = await importBook(path, (p, l) {
        if (mounted) {
          setState(() {
            _progress = p;
            _label = l;
          });
        }
      });
      Uint8List? cover;
      if (path.toLowerCase().endsWith('.pdf')) {
        setState(() => _label = 'Preparando la portada…');
        cover = await renderPdfCover(path);
      }
      final meta = await Library.I.add(r, cover: cover);
      if (!mounted) return;
      setState(() => _progress = null);
      _open(meta);
    } on ImportError catch (e) {
      setState(() {
        _progress = null;
        _error = e.isEmpty
            ? 'Este archivo no tiene texto para leer. Seguramente es un PDF escaneado (fotos de páginas).'
            : 'No pude abrir «$_importName». Revisá que no tenga contraseña ni protección DRM (como los libros de Kindle o Google Play).';
      });
    } catch (_) {
      setState(() {
        _progress = null;
        _error = 'No pude abrir «$_importName». Probá con otro archivo.';
      });
    }
  }

  void _open(BookMeta m) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(meta: m)));
  }

  Future<void> _menu(BookMeta m) async {
    final p = pal(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(children: [
              BookCover(meta: m, width: 44, radius: 6, shadow: false),
              const SizedBox(width: 14),
              Expanded(child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(size: 17, weight: FontWeight.w600, color: p.fg))),
            ]),
          ),
          ListTile(leading: const Icon(Icons.play_arrow_rounded), title: const Text('Abrir'), onTap: () => Navigator.pop(c, 'open')),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: p.accent),
            title: Text('Borrar del celular', style: TextStyle(color: p.accent)),
            onTap: () => Navigator.pop(c, 'del'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == 'open') _open(m);
    if (action == 'del') {
      if (ReaderEngine.I.meta?.id == m.id) ReaderEngine.I.close();
      await Library.I.remove(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _progress == null ? _add : null,
        backgroundColor: p.fg,
        foregroundColor: p.bg,
        elevation: 2,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Agregar libro', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([Library.I, ReaderEngine.I]),
        builder: (context, _) {
          final books = Library.I.books;
          final e = ReaderEngine.I;
          BookMeta? cont = e.meta;
          if (cont == null) {
            for (final b in books) {
              if (b.position > 0) {
                cont = b;
                break;
              }
            }
          }
          final totalMin = books.fold<int>(0, (a, b) => a + (b.chars * (1 - b.progress) / 950).round());
          return SafeArea(
            bottom: false,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Biblioteca',
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: p.fg)),
                        const SizedBox(height: 2),
                        Text(
                          books.isEmpty
                              ? 'Tus libros, para escuchar'
                              : '${books.length} ${books.length == 1 ? 'libro' : 'libros'} · ${fmtMinutes(totalMin)} por escuchar',
                          style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Apariencia',
                      onPressed: () => showDisplaySheet(context),
                      icon: const Icon(Icons.palette_outlined),
                    ),
                  ]),
                ),
              ),
              if (cont != null) SliverToBoxAdapter(child: _ContinueCard(meta: cont, onOpen: () => _open(cont!))),
              if (_progress != null) SliverToBoxAdapter(child: _ImportCard(name: _importName ?? '', progress: _progress!, label: _label)),
              if (_error != null)
                SliverToBoxAdapter(
                  child: _Notice(text: _error!, onClose: () => setState(() => _error = null)),
                ),
              if (books.isEmpty && _progress == null)
                SliverFillRemaining(hasScrollBody: false, child: _Empty(onAdd: _add))
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Text('TUS LIBROS', style: label(p.muted)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: 18,
                      childAspectRatio: 0.47,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _BookTile(meta: books[i], onTap: () => _open(books[i]), onMenu: () => _menu(books[i])),
                      childCount: books.length,
                    ),
                  ),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------ seguir escuchando

class _ContinueCard extends StatelessWidget {
  final BookMeta meta;
  final VoidCallback onOpen;
  const _ContinueCard({required this.meta, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final e = ReaderEngine.I;
    final isCurrent = e.meta?.id == meta.id;
    final playing = isCurrent && e.playing;
    final left = (meta.chars * (1 - meta.progress) / 950).round();
    final h = meta.hue.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          height: 196,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28)),
          child: Stack(fit: StackFit.expand, children: [
            if (meta.hasCover)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: Transform.scale(
                  scale: 1.4,
                  child: Image.file(File(Library.I.coverPath(meta.id)), fit: BoxFit.cover, cacheWidth: 200),
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    HSLColor.fromAHSL(1, h, 0.45, 0.35).toColor(),
                    HSLColor.fromAHSL(1, (h + 35) % 360, 0.5, 0.18).toColor(),
                  ]),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.6)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                BookCover(meta: meta, width: 100, radius: 10),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(playing ? 'ESCUCHANDO' : 'SEGUÍ ESCUCHANDO', style: label(Colors.white.withValues(alpha: 0.8))),
                    const SizedBox(height: 6),
                    Text(meta.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serif(size: 20, weight: FontWeight.w600, color: Colors.white, height: 1.2)),
                    if (isCurrent && e.sectionTitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(e.sectionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                    ],
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: meta.progress,
                        minHeight: 4,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Text('${(meta.progress * 100).round()} % · faltan ${fmtMinutes(left)}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async {
                            if (!isCurrent) await e.open(meta);
                            if (context.mounted) await playOrAskVoice(context);
                          },
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 30),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ grilla

class _BookTile extends StatelessWidget {
  final BookMeta meta;
  final VoidCallback onTap, onMenu;
  const _BookTile({required this.meta, required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final pct = (meta.progress * 100).round();
    String? chip;
    if (meta.isEnglish) {
      chip = meta.translated == 0 ? 'EN' : (meta.fullyTranslated ? 'ES' : '${(meta.translated * 100 / meta.paraCount).round()} %');
    }
    return GestureDetector(
      onTap: onTap,
      onLongPress: onMenu,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            BookCover(meta: meta, radius: 14),
            if (chip != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.translate_rounded, size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(chip, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: meta.progress, minHeight: 3, color: p.accent, backgroundColor: p.line),
        ),
        const SizedBox(height: 8),
        Text(meta.title,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.25, color: p.fg)),
        const SizedBox(height: 2),
        Text(
          pct == 0 ? (meta.author.isNotEmpty ? meta.author : 'Sin empezar') : '$pct % escuchado',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _ImportCard extends StatelessWidget {
  final String name, label;
  final double progress;
  const _ImportCard({required this.name, required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Importando «$name»', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 6, color: p.accent, backgroundColor: p.line),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _Notice({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: BoxDecoration(color: p.hl, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: p.accent),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(color: p.hl, shape: BoxShape.circle),
          child: Icon(Icons.headphones_rounded, size: 46, color: p.accent),
        ),
        const SizedBox(height: 24),
        Text('Tu biblioteca está vacía', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.fg)),
        const SizedBox(height: 8),
        Text(
          'Agregá un PDF, EPUB o TXT desde Archivos, iCloud o Drive y escuchalo con una voz natural. Si está en inglés, te lo traduzco.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Agregar mi primer libro')),
      ]),
    );
  }
}
