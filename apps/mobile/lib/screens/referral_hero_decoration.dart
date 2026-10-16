import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Dimensions and rotations from the supplied prototype's .hero-art:before.
class ReferralHeroDecoration extends Decoration {
  const ReferralHeroDecoration();

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ReferralHeroPainter();
}

class _ReferralHeroPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final bounds =
        RRect.fromRectAndRadius(offset & size, const Radius.circular(18));
    canvas.drawRRect(bounds, Paint()..color = navy);
    canvas.save();
    canvas.clipRRect(bounds);
    canvas.translate(offset.dx + size.width - 118 + 62.5,
        offset.dy + size.height - 146 + 62.5);
    canvas.rotate(18 * math.pi / 180);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-62.5, -62.5, 125, 125),
            const Radius.circular(40)),
        Paint()
          ..color = const Color(0xFF4D648B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    canvas.restore();
  }
}
