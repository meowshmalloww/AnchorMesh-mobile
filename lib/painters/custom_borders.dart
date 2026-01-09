import 'dart:math';
import 'package:flutter/material.dart';

/// Hexagonal Bevel Border
///
/// A 6-point polygon with soft beveled edges that feels tactical
/// and premium. Not a simple circle or rounded rectangle.
class HexagonalBevelBorder extends ShapeBorder {
  final double bevelDepth;
  final double cornerRadius;
  final BorderSide side;

  const HexagonalBevelBorder({
    this.bevelDepth = 0.15, // How much to cut corners (0-0.5)
    this.cornerRadius = 4.0,
    this.side = BorderSide.none,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _getPath(Rect rect) {
    final path = Path();
    final w = rect.width;
    final h = rect.height;
    final bevel = min(w, h) * bevelDepth;

    // Start from top-left after bevel
    path.moveTo(rect.left + bevel, rect.top);

    // Top edge to top-right bevel
    path.lineTo(rect.right - bevel, rect.top);

    // Top-right corner (beveled)
    path.quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + bevel);

    // Right edge to bottom-right bevel
    path.lineTo(rect.right, rect.bottom - bevel);

    // Bottom-right corner (beveled)
    path.quadraticBezierTo(
      rect.right,
      rect.bottom,
      rect.right - bevel,
      rect.bottom,
    );

    // Bottom edge to bottom-left bevel
    path.lineTo(rect.left + bevel, rect.bottom);

    // Bottom-left corner (beveled)
    path.quadraticBezierTo(
      rect.left,
      rect.bottom,
      rect.left,
      rect.bottom - bevel,
    );

    // Left edge to top-left bevel
    path.lineTo(rect.left, rect.top + bevel);

    // Top-left corner (beveled)
    path.quadraticBezierTo(rect.left, rect.top, rect.left + bevel, rect.top);

    path.close();
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect.deflate(side.width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;

    final paint = side.toPaint();
    canvas.drawPath(_getPath(rect), paint);
  }

  @override
  ShapeBorder scale(double t) {
    return HexagonalBevelBorder(
      bevelDepth: bevelDepth,
      cornerRadius: cornerRadius * t,
      side: side.scale(t),
    );
  }
}

/// Pill Chamfer Border
///
/// A rounded rectangle with 45° chamfered corners instead of
/// pure curves. Looks like a machined metal component.
class PillChamferBorder extends ShapeBorder {
  final double chamferSize;
  final BorderSide side;

  const PillChamferBorder({
    this.chamferSize = 8.0,
    this.side = BorderSide.none,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _getPath(Rect rect) {
    final path = Path();
    final chamfer = min(chamferSize, min(rect.width, rect.height) / 4);
    final radius = rect.height / 2;

    // Start from top-left after chamfer
    path.moveTo(rect.left + chamfer, rect.top);

    // Top edge
    path.lineTo(rect.right - radius, rect.top);

    // Right semicircle
    path.arcToPoint(
      Offset(rect.right - radius, rect.bottom),
      radius: Radius.circular(radius),
      clockwise: true,
    );

    // Bottom edge
    path.lineTo(rect.left + chamfer, rect.bottom);

    // Bottom-left chamfer
    path.lineTo(rect.left, rect.bottom - chamfer);

    // Left edge
    path.lineTo(rect.left, rect.top + chamfer);

    // Top-left chamfer
    path.lineTo(rect.left + chamfer, rect.top);

    path.close();
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect.deflate(side.width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;

    final paint = side.toPaint();
    canvas.drawPath(_getPath(rect), paint);
  }

  @override
  ShapeBorder scale(double t) {
    return PillChamferBorder(chamferSize: chamferSize * t, side: side.scale(t));
  }
}

/// Tactical Card Border
///
/// An asymmetric border with beveled corners only on select edges,
/// giving a "cut" or "machined" appearance.
class TacticalCardBorder extends ShapeBorder {
  final double topLeftBevel;
  final double bottomRightBevel;
  final double radius;
  final BorderSide side;

  const TacticalCardBorder({
    this.topLeftBevel = 16.0,
    this.bottomRightBevel = 16.0,
    this.radius = 12.0,
    this.side = BorderSide.none,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _getPath(Rect rect) {
    final path = Path();

    // Start at top-left bevel point
    path.moveTo(rect.left + topLeftBevel, rect.top);

    // Top edge to top-right rounded corner
    path.lineTo(rect.right - radius, rect.top);
    path.quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + radius);

    // Right edge to bottom-right bevel
    path.lineTo(rect.right, rect.bottom - bottomRightBevel);
    path.lineTo(rect.right - bottomRightBevel, rect.bottom);

    // Bottom edge to bottom-left rounded corner
    path.lineTo(rect.left + radius, rect.bottom);
    path.quadraticBezierTo(
      rect.left,
      rect.bottom,
      rect.left,
      rect.bottom - radius,
    );

    // Left edge to top-left bevel
    path.lineTo(rect.left, rect.top + topLeftBevel);
    path.lineTo(rect.left + topLeftBevel, rect.top);

    path.close();
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect.deflate(side.width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;

    final paint = side.toPaint();
    canvas.drawPath(_getPath(rect), paint);
  }

  @override
  ShapeBorder scale(double t) {
    return TacticalCardBorder(
      topLeftBevel: topLeftBevel * t,
      bottomRightBevel: bottomRightBevel * t,
      radius: radius * t,
      side: side.scale(t),
    );
  }
}
