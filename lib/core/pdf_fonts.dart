import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Fonts for printed receipts and kitchen tokens. They ship inside the app,
/// so Bangla and Latin text print correctly with no network. Noto Sans
/// covers English, Noto Sans Bengali covers Bangla, and the PDF library
/// falls back to it for any character the first font lacks.
class PdfFonts {
  const PdfFonts._();

  static pw.ThemeData? _theme;

  static Future<pw.Font> _load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));

  static Future<pw.ThemeData> theme() async {
    final cached = _theme;
    if (cached != null) {
      return cached;
    }
    final theme = pw.ThemeData.withFont(
      base: await _load('NotoSans-Regular.ttf'),
      bold: await _load('NotoSans-Bold.ttf'),
      fontFallback: [await _load('NotoSansBengali-Regular.ttf')],
    );
    _theme = theme;
    return theme;
  }
}
