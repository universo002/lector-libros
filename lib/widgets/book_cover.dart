import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Tapa generada a partir del título (cada libro tiene su color).
class BookCover extends StatelessWidget {
  final BookMeta meta;
  final double width;
  const BookCover({super.key, required this.meta, this.width = 64});

  @override
  Widget build(BuildContext context) {
    final h = meta.hue.toDouble();
    final c1 = HSLColor.fromAHSL(1, h, 0.42, 0.34).toColor();
    final c2 = HSLColor.fromAHSL(1, (h + 28) % 360, 0.48, 0.22).toColor();
    final height = width * 1.5;
    final small = width < 80;
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(small ? 6 : 10),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(width: small ? 4 : 6, color: Colors.black.withValues(alpha: 0.18)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(small ? 9 : 14, small ? 8 : 14, small ? 6 : 12, small ? 6 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  meta.title,
                  maxLines: small ? 4 : 5,
                  overflow: TextOverflow.fade,
                  style: serif(size: small ? 9.5 : 15, weight: FontWeight.w600, color: Colors.white, height: 1.2),
                ),
              ),
              Text(
                meta.format,
                style: TextStyle(fontSize: small ? 7 : 10, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
