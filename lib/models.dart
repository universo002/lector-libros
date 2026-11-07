class Section {
  final String title;
  final int start; // índice del primer párrafo
  const Section(this.title, this.start);

  Map<String, dynamic> toJson() => {'t': title, 's': start};
  factory Section.fromJson(Map<String, dynamic> m) => Section(m['t'] as String, (m['s'] as num).toInt());
}

/// Texto completo del libro, dividido en párrafos.
class BookContent {
  final List<Section> sections;
  final List<String> paras;
  final List<int> prefix; // caracteres acumulados, para calcular tiempos

  BookContent(this.sections, this.paras) : prefix = _prefix(paras);

  static List<int> _prefix(List<String> p) {
    final r = List<int>.filled(p.length + 1, 0);
    for (var i = 0; i < p.length; i++) {
      r[i + 1] = r[i] + p[i].length;
    }
    return r;
  }

  /// Índice de la sección que contiene el párrafo [i].
  int sectionOf(int i) {
    var lo = 0, hi = sections.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (sections[mid].start <= i) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  int sectionEnd(int s) => s + 1 < sections.length ? sections[s + 1].start : paras.length;

  factory BookContent.fromJson(Map<String, dynamic> m) => BookContent(
        (m['sections'] as List).map((s) => Section.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
        (m['paras'] as List).cast<String>(),
      );
}

/// Datos livianos del libro que se muestran en la biblioteca.
class BookMeta {
  final String id;
  String title;
  String author;
  final String format;
  final String lang; // 'en', 'es' u 'otro'
  final int paraCount;
  final int chars;
  final int pages;
  final int hue;
  int position;
  int translated;
  bool useTranslation;
  bool hasCover;
  List<int> bookmarks;
  DateTime added;
  DateTime opened;

  BookMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.lang,
    required this.paraCount,
    required this.chars,
    required this.pages,
    required this.hue,
    this.position = 0,
    this.translated = 0,
    this.useTranslation = false,
    this.hasCover = false,
    List<int>? bookmarks,
    DateTime? added,
    DateTime? opened,
  })  : bookmarks = bookmarks ?? [],
        added = added ?? DateTime.now(),
        opened = opened ?? DateTime.now();

  double get progress => paraCount <= 1 ? 0 : position / (paraCount - 1);
  bool get isEnglish => lang == 'en';
  bool get fullyTranslated => translated >= paraCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format,
        'lang': lang,
        'paraCount': paraCount,
        'chars': chars,
        'pages': pages,
        'hue': hue,
        'position': position,
        'translated': translated,
        'useTranslation': useTranslation,
        'hasCover': hasCover,
        'bookmarks': bookmarks,
        'added': added.toIso8601String(),
        'opened': opened.toIso8601String(),
      };

  factory BookMeta.fromJson(Map<String, dynamic> m) => BookMeta(
        id: m['id'] as String,
        title: m['title'] as String,
        author: (m['author'] ?? '') as String,
        format: (m['format'] ?? '') as String,
        lang: (m['lang'] ?? 'es') as String,
        paraCount: (m['paraCount'] as num).toInt(),
        chars: ((m['chars'] ?? 0) as num).toInt(),
        pages: ((m['pages'] ?? 0) as num).toInt(),
        hue: ((m['hue'] ?? 150) as num).toInt(),
        position: ((m['position'] ?? 0) as num).toInt(),
        translated: ((m['translated'] ?? 0) as num).toInt(),
        useTranslation: (m['useTranslation'] ?? false) as bool,
        hasCover: (m['hasCover'] ?? false) as bool,
        bookmarks: ((m['bookmarks'] ?? []) as List).map((e) => (e as num).toInt()).toList(),
        added: DateTime.tryParse((m['added'] ?? '') as String),
        opened: DateTime.tryParse((m['opened'] ?? '') as String),
      );
}
