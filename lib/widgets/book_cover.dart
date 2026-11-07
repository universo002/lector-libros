import 'dart:io';

import 'package:flutter/material.dart';

import '../library.dart';
import '../models.dart';
import '../theme.dart';

/// Portada del libro: la real si el archivo tenía una, si no, una generada.
class BookCover extends StatelessWidget {
  final BookMeta meta;
  final double? width; // null = ocupa el espacio que le den
  final double radius;
  final bool shadow;

  const BookCover({super.key, required this.meta, this.width, this.radius = 12, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    Widget inner = LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : (width ?? 120);
      if (meta.hasCover) {
        return Image.file(
          File(Library.I.coverPath(meta.id)),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: (w * 3).round(),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _Generated(meta: meta, w: w),
        );
      }
      return _Generated(meta: meta, w: w);
    });

    inner = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [
                BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 8)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 3, offset: const Offset(0, 1)),
              ]
            : null,
      ),
      child: inner,
    );

    if (width != null) return SizedBox(width: width, height: width! * 1.5, child: inner);
    return inner;
  }
}

class _Generated extends StatelessWidget {
  final BookMeta meta;
  final double w;
  const _Generated({required this.meta, required this.w});

  @override
  Widget build(BuildContext context) {
    final h = meta.hue.toDouble();
    final c1 = HSLColor.fromAHSL(1, h, 0.45, 0.38).toColor();
    final c2 = HSLColor.fromAHSL(1, (h + 35) % 360, 0.50, 0.20).toColor();
    final small = w < 90;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
      ),
      padding: EdgeInsets.fromLTRB(small ? 8 : 14, small ? 10 : 16, small ? 8 : 14, small ? 8 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: small ? 14 : 24, height: 2, color: Colors.white.withValues(alpha: 0.7)),
        SizedBox(height: small ? 6 : 12),
        Expanded(
          child: Text(
            meta.title,
            maxLines: small ? 4 : 6,
            overflow: TextOverflow.fade,
            style: serif(size: small ? 9.5 : (w / 9).clamp(13, 22).toDouble(), weight: FontWeight.w600, color: Colors.white, height: 1.18),
          ),
        ),
        if (meta.author.isNotEmpty && !small)
          Text(
            meta.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
          ),
      ]),
    );
  }
}
