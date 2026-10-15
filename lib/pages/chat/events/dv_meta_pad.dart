// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: поля вокруг текста пузыря и место под время с галочками.
// Время садится в строку с последней строкой текста, если там хватает места
// (замер по настоящей вёрстке текста). Если не хватает, под текстом остаётся свободная строка.

import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

class DvMetaPad extends SingleChildRenderObjectWidget {
  const DvMetaPad({required this.metaWidth, super.child, super.key});

  /// Сколько места нужно метке справа от последней строки (0 — метки нет)
  final double metaWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMetaPad(metaWidth);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMetaPad).metaWidth = metaWidth;
  }
}

class _RenderMetaPad extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderMetaPad(this._metaWidth);

  static const double _padX = 16;
  static const double _padY = 8;
  static const double _extra = 14;

  double _metaWidth;
  set metaWidth(double value) {
    if (value == _metaWidth) return;
    _metaWidth = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  /// Правый край последней строки текста внутри [root] или null, если текста не нашли
  static double? _lastLineRight(RenderBox root) {
    final rects = <Rect>[];
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        final length = node.text.toPlainText().length;
        if (length > 0) {
          final boxes = node.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: length),
          );
          final matrix = node.getTransformTo(root);
          for (final box in boxes) {
            rects.add(MatrixUtils.transformRect(matrix, box.toRect()));
          }
        }
      }
      node.visitChildren(visit);
    }

    visit(root);
    if (rects.isEmpty) return null;
    final lastCenter = rects.map((r) => r.center.dy).reduce(max);
    var right = 0.0;
    for (final r in rects) {
      if (r.center.dy >= lastCenter - 7) right = max(right, r.right);
    }
    return right;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(const Size(_padX * 2, _padY * 2));
      return;
    }
    final maxInner = max(0.0, constraints.maxWidth - _padX * 2);
    child.layout(BoxConstraints(maxWidth: maxInner), parentUsesSize: true);
    var width = child.size.width;
    var extra = 0.0;
    if (_metaWidth > 0) {
      final lastRight = _lastLineRight(child);
      if (lastRight == null || lastRight + _metaWidth > maxInner + _padX) {
        extra = _extra;
      } else {
        width = max(width, lastRight + _metaWidth - _padX);
      }
    }
    (child.parentData! as BoxParentData).offset = const Offset(_padX, _padY);
    size = constraints.constrain(
      Size(width + _padX * 2, child.size.height + _padY * 2 + extra),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(max(0.0, height - _padY * 2)) ?? 0) +
      _padX * 2;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(max(0.0, height - _padY * 2)) ?? 0) +
      _padX * 2 +
      _metaWidth;

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(max(0.0, width - _padX * 2)) ?? 0) +
      _padY * 2 +
      (_metaWidth > 0 ? _extra : 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(max(0.0, width - _padX * 2)) ?? 0) +
      _padY * 2 +
      (_metaWidth > 0 ? _extra : 0);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = max(0.0, constraints.maxWidth - _padX * 2);
    final childSize =
        child?.getDryLayout(BoxConstraints(maxWidth: inner)) ?? Size.zero;
    return constraints.constrain(
      Size(childSize.width + _padX * 2, childSize.height + _padY * 2),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(
      child,
      (child.parentData! as BoxParentData).offset + offset,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final offset = (child.parentData! as BoxParentData).offset;
    return result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}
