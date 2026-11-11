/// Procedural weave texture.
///
/// A weave draft *is* a boolean matrix of over/under, so weave structure is
/// naturally expressed as a function rather than a bitmap (docs/03 §4b). That
/// makes this theme one of the few where procedural texture is not a
/// compromise, and it is why the game ships no texture assets at all.
///
/// ## Where texture goes — and does not
///
/// **Yes:** the board background behind empty cells, the loom frame and
/// margins, the title screen, shop and draft cards, run-summary panels —
/// anywhere a surface is large and still.
///
/// **No:** filled cells at play size, the dragged piece, the ghost. A 42px
/// cell is too small for weave structure to read as anything but noise, and it
/// will crawl while a piece is being dragged.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum Weave { tabby, twill, basket, satin, rib, herringbone }

/// `true` = warp thread on top.
///
/// **Port note.** Dart's `%` is Euclidean and always returns a non-negative
/// result, so `(x - y) % 4` is safe for negative inputs. TypeScript's is not —
/// `-1 % 4 === -1` — so any version of this written in the prototype needs the
/// double-mod `((n % m) + m) % m`, and that double-mod can be *removed* here
/// rather than carried over. This is exactly the class of silent difference
/// the port's histogram check exists to catch (spec §6).
bool warpUp(int x, int y, Weave w) => switch (w) {
  Weave.tabby => (x + y) % 2 == 0, // plain over-under
  Weave.twill => (x - y) % 4 < 2, // diagonal rib
  Weave.basket => (x ~/ 2 + y ~/ 2) % 2 == 0, // 2x2 blocks
  Weave.satin => (x - y * 2) % 5 == 0, // scattered, lustrous
  Weave.rib => y % 4 < 2, // horizontal banding
  Weave.herringbone => ((x % 8 < 4 ? x : 7 - x) - y) % 4 < 2,
};

/// The repeat of each structure, in weave units.
int repeatOf(Weave w) => switch (w) {
  Weave.tabby => 2,
  Weave.twill => 4,
  Weave.basket => 4,
  Weave.satin => 5,
  Weave.rib => 4,
  Weave.herringbone => 8,
};

/// A repeating weave fill, built once and reused.
///
/// Cost at paint time is one texture lookup. Build it at startup — never per
/// frame — and dispose it with the widget that owns it.
class WeaveShader {
  WeaveShader._(this.image, this.paint, this.tilePx);

  final ui.Image image;
  final Paint paint;
  final int tilePx;

  /// Render the tile once into a [ui.Image] and wrap it in a repeating
  /// [ImageShader].
  ///
  /// Generate the tile at **integer device pixels** and keep the thread unit
  /// at ≥ 4px, or a 1px feature scaled by a fractional DPR will shimmer and
  /// moiré during drags.
  static Future<WeaveShader> create({
    required Weave weave,
    required Color warp,
    required Color weft,
    double devicePixelRatio = 1.0,
    int threadPx = 4,
  }) async {
    final unit = (threadPx * devicePixelRatio).round().clamp(4, 32);
    final repeat = repeatOf(weave);
    final size = unit * repeat;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = weft,
    );
    final warpPaint = Paint()..color = warp;
    for (var y = 0; y < repeat; y++) {
      for (var x = 0; x < repeat; x++) {
        if (!warpUp(x, y, weave)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (x * unit).toDouble(),
            (y * unit).toDouble(),
            unit.toDouble(),
            unit.toDouble(),
          ),
          warpPaint,
        );
      }
    }

    final image = await recorder.endRecording().toImage(size, size);

    // Scale the shader back down by the DPR so the texture measures the same
    // in logical pixels whatever the screen.
    final m = Matrix4.identity()
      ..scaleByDouble(
        1 / devicePixelRatio,
        1 / devicePixelRatio,
        1.0,
        1.0,
      );

    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        m.storage,
      );

    return WeaveShader._(image, paint, size);
  }

  void dispose() => image.dispose();
}

/// Warp lines for the loom frame and margins — the still surfaces where
/// structure is allowed to read.
///
/// Pre-recorded into a [ui.Picture] by the caller and replayed with
/// `drawPicture`, so the static chrome costs nothing per frame (spec §8).
void paintWarpLines(
  Canvas canvas,
  Rect area, {
  required Color line,
  double spacing = 7.0,
  double width = 1.0,
}) {
  final paint = Paint()
    ..color = line
    ..strokeWidth = width;
  for (var x = area.left; x <= area.right; x += spacing) {
    canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), paint);
  }
}
