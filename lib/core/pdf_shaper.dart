import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf/widgets.dart' as pw;

/// Puts Bangla text on a printed page.
///
/// The PDF library draws glyphs one by one and cannot reorder Bengali vowel
/// signs or join conjuncts, so Bangla words come out with the wrong letter
/// order. Flutter's text engine shapes Bengali correctly, so each Bangla
/// string is drawn with it into a sharp image and placed in the PDF. Plain
/// Latin text stays real, selectable PDF text.
class PdfShaper {
  PdfShaper();

  static final _bengali = RegExp(r'[ঀ-৿]');

  /// Images are drawn at this multiple of the print size so they stay crisp.
  static const _scale = 4.0;

  final Map<String, ({pw.MemoryImage image, double width, double height})> _images = {};

  static bool needsShaping(String text) => _bengali.hasMatch(text);

  static String _key(String text, double size, bool bold, double maxWidth) =>
      '$text|$size|$bold|$maxWidth';

  /// Draws [text] now so [text] can be used synchronously while the page is
  /// built. [maxWidth] is the usable page width in PDF points.
  Future<void> prepare(String text, double size, {bool bold = false, required double maxWidth}) async {
    if (!needsShaping(text)) {
      return;
    }
    final key = _key(text, size, bold, maxWidth);
    if (_images.containsKey(key)) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          // The system font carries Bengali on Android and iOS.
          fontFamily: 'sans-serif',
          color: const Color(0xFF000000),
          fontSize: size * _scale,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth * _scale);

    final width = painter.width.ceilToDouble();
    final height = painter.height.ceilToDouble();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    final image = await recorder.endRecording().toImage(width.toInt().clamp(1, 8192), height.toInt().clamp(1, 8192));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    painter.dispose();
    if (data == null) {
      return;
    }
    _images[key] = (
      image: pw.MemoryImage(data.buffer.asUint8List()),
      width: width / _scale,
      height: height / _scale,
    );
  }

  /// A text widget: the prepared image for Bangla, ordinary text otherwise.
  pw.Widget text(
    String text,
    double size, {
    bool bold = false,
    required double maxWidth,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    final hit = _images[_key(text, size, bold, maxWidth)];
    if (hit == null) {
      return pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      );
    }
    final image = pw.Image(hit.image, width: hit.width, height: hit.height);
    return switch (align) {
      pw.TextAlign.center => pw.Center(child: image),
      pw.TextAlign.right => pw.Align(alignment: pw.Alignment.centerRight, child: image),
      _ => pw.Align(alignment: pw.Alignment.centerLeft, child: image),
    };
  }
}
