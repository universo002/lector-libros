import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../importer.dart';
import '../library.dart';
import '../models.dart';
import '../reader_engine.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import 'reader_screen.dart';

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
        if (mounted) setState(() {
          _progress = p;
          _label = l;
        });
      });
      final meta = await Library.I.add(r);
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

  Future<void> _delete(BookMeta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar este libro?'),
        content: Text('Se borra «${m.title}» del celular, con su traducción y marcadores.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    if (ReaderEngine.I.meta?.id == m.id) ReaderEngine.I.close();
    await Library.I.remove(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _progress == null ? _add : null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Agregar libro'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([Library.I, ReaderEngine.I]),
        builder: (context, _) {
          final books = Library.I.books;
          final e = ReaderEngine.I;
          return CustomScrollView(slivers: [
            SliverAppBar.large(
              title: Text('Mis libros', style: serif(size: 30, weight: FontWeight.w600, color: p.fg)),
              backgroundColor: p.bg,
            ),
            if (e.meta != null) SliverToBoxAdapter(child: _NowPlaying(onOpen: () => _open(e.meta!))),
            if (_progress != null)
              SliverToBoxAdapter(
                child: _Card(children: [
                  Text('Importando «$_importName»', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 6),
                  ),
                  const SizedBox(height: 8),
                  Text(_label, style: TextStyle(color: p.muted, fontSize: 13)),
                ]),
              ),
            if (_error != null)
              SliverToBoxAdapter(
                child: _Card(children: [
                  Row(children: [
                    Icon(Icons.info_outline_rounded, color: p.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                    IconButton(onPressed: () => setState(() => _error = null), icon: const Icon(Icons.close_rounded)),
                  ]),
                ]),
              ),
            if (books.isEmpty && _progress == null)
              SliverFillRemaining(hasScrollBody: false, child: _Empty(onAdd: _add))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList.separated(
                  itemCount: books.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: p.line),
                  itemBuilder: (context, i) => _BookTile(
                    meta: books[i],
                    onTap: () => _open(books[i]),
                    onDelete: () => _delete(books[i]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final VoidCallback onOpen;
  const _NowPlaying({required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = ReaderEngine.I;
    final m = e.meta!, c = e.content!;
    final section = c.sections[c.sectionOf(e.idx)].title;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.highlight, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          BookCover(meta: m, width: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.playing ? 'ESCUCHANDO' : 'SEGUÍ DONDE QUEDASTE',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.accent)),
              const SizedBox(height: 4),
              Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(size: 16, weight: FontWeight.w600, color: p.fg)),
              Text(section, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          ),
          IconButton.filled(
            iconSize: 30,
            onPressed: e.toggle,
            icon: Icon(e.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
        ]),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final BookMeta meta;
  final VoidCallback onTap, onDelete;
  const _BookTile({required this.meta, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final pct = (meta.progress * 100).round();
    final left = (meta.chars * (1 - meta.progress) / 950).round();
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BookCover(meta: meta),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(meta.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(size: 17, weight: FontWeight.w600, color: p.fg, height: 1.25)),
              if (meta.author.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(meta.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: meta.progress, minHeight: 4, backgroundColor: p.line),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(pct == 0 ? 'Sin empezar · ${fmtMinutes(left)}' : '$pct % · faltan ${fmtMinutes(left)}',
                    style: TextStyle(color: p.muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
                if (meta.pages > 0) Text('${fmtThousands(meta.pages)} pág.', style: TextStyle(color: p.muted, fontSize: 12.5)),
                if (meta.isEnglish) _Chip(meta.translated == 0 ? 'Inglés' : (meta.fullyTranslated ? 'Traducido' : 'Traduciendo ${(meta.translated * 100 / meta.paraCount).round()} %')),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: p.muted),
            onSelected: (v) => v == 'del' ? onDelete() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Borrar libro'))],
          ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: p.highlight, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.accent)),
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
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: p.highlight, shape: BoxShape.circle),
          child: Icon(Icons.headphones_rounded, size: 44, color: p.accent),
        ),
        const SizedBox(height: 24),
        Text('Tu biblioteca está vacía', style: serif(size: 22, weight: FontWeight.w600, color: p.fg)),
        const SizedBox(height: 8),
        Text(
          'Agregá un PDF, EPUB o TXT desde Archivos, iCloud o Drive y escuchalo como audiolibro. Si está en inglés, te lo traduzco.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Agregar mi primer libro')),
      ]),
    );
  }
}
