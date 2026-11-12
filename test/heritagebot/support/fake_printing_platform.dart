// HERITAGEBOT - TEST SUPPORT: operating-system print / save-as-PDF dialog
// fake for CASE-073 / CASE-074 (Administrator Dashboard / Generate Report).
//
// The real AdminAnalyticsScreen "Generate PDF Report" tile calls the real
// AdminReportService.generateSystemReport (lib/, unmodified), which builds
// the PDF with package:pdf and then hands it to Printing.layoutPdf - the
// phone's native print / "Save as PDF" dialog. That native dialog is the
// only thing replaced here (PrintingPlatform.instance), exactly like
// FakeImagePickerPlatform replaces the phone's gallery picker:
//
//   * FakePrintingPlatform.layoutPdf asks HeritageBot's onLayout callback
//     for the document (as the native dialog does), records the bytes and
//     the document name, and answers "printed / saved" (true).
//   * It never builds, edits, filters or judges the report.
//
// readPdfLines() then reads the text HeritageBot actually wrote into that
// PDF so tests can check which records the report contains.

// printing is a direct dependency of HeritageBot (pubspec.yaml unchanged).
// PrintingPlatform is the package's documented platform-interface base
// class; it lives in src/interface.dart.
// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

/// One document HeritageBot sent to the print / save dialog.
class FakePrintJob {
  FakePrintJob({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  bool get isPdf =>
      bytes.length > 5 && latin1.decode(bytes.sublist(0, 5)) == '%PDF-';

  /// Text lines of the PDF (see [readPdfLines]). Words of neighbouring table
  /// cells that share a baseline appear on the same line, so use [words]
  /// for exact checks.
  List<String> get lines => readPdfLines(bytes);

  /// Every word HeritageBot drew in the PDF (package:pdf draws each
  /// space-separated word as its own text run).
  Set<String> get words => readPdfWords(bytes);

  @override
  String toString() =>
      'FakePrintJob(name=$name, bytes=${bytes.length}, isPdf=$isPdf)';
}

class FakePrintingPlatform extends PrintingPlatform {
  final List<FakePrintJob> jobs = <FakePrintJob>[];

  void clear() => jobs.clear();

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    final bytes = await onLayout(format);
    jobs.add(FakePrintJob(name: name, bytes: bytes));
    return true;
  }

  @override
  Future<PrintingInfo> info() async => const PrintingInfo(
    canPrint: true,
    canShare: true,
    canRaster: false,
    canListPrinters: false,
    directPrint: false,
    dynamicLayout: true,
  );

  @override
  Future<List<Printer>> listPrinters() async => const <Printer>[];

  @override
  Future<Printer?> pickPrinter(Rect bounds) async => null;

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    jobs.add(FakePrintJob(name: filename, bytes: bytes));
    return true;
  }

  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) => throw UnsupportedError('convertHtml is not used by HeritageBot.');

  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) => throw UnsupportedError('raster is not used by HeritageBot.');
}

// ---------------------------------------------------------------------------
// PDF TEXT
// ---------------------------------------------------------------------------

final RegExp _streamStart = RegExp(r'stream\r?\n');
final RegExp _textRun = RegExp(
  r'(-?[\d.]+) (-?[\d.]+) Td \[\(((?:\\.|[^\\)])*)\)\]TJ',
);

String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => m.group(1)!,
);

/// Every text run (word) of a PDF written by package:pdf.
Set<String> readPdfWords(Uint8List bytes) => _contentStreams(bytes)
    .expand((content) => _textRun.allMatches(content))
    .map((run) => _unescape(run.group(3)!))
    .toSet();

Iterable<String> _contentStreams(Uint8List bytes) sync* {
  final raw = latin1.decode(bytes);
  for (final match in _streamStart.allMatches(raw)) {
    final end = raw.indexOf('endstream', match.end);
    if (end < 0) continue;
    try {
      yield latin1.decode(
        ZLibDecoder().convert(bytes.sublist(match.end, end)),
      );
    } catch (_) {
      // fonts / images: not text content
    }
  }
}

/// Text lines of a PDF written by package:pdf: every content stream is
/// inflated and the words drawn at the same vertical position are joined
/// left-to-right (one table row / one paragraph line per entry).
List<String> readPdfLines(Uint8List bytes) {
  final lines = <String>[];

  for (final content in _contentStreams(bytes)) {
    // y -> (x, word) for this page / stream.
    final rows = <double, List<MapEntry<double, String>>>{};
    final order = <double>[];
    for (final run in _textRun.allMatches(content)) {
      final x = double.parse(run.group(1)!);
      final y = double.parse(run.group(2)!);
      final key = (y * 10).roundToDouble() / 10;
      if (!rows.containsKey(key)) order.add(key);
      rows.putIfAbsent(key, () => []).add(MapEntry(x, _unescape(run.group(3)!)));
    }
    order.sort((a, b) => b.compareTo(a)); // top of the page first
    for (final y in order) {
      final words = rows[y]!..sort((a, b) => a.key.compareTo(b.key));
      lines.add(words.map((w) => w.value).join(' '));
    }
  }
  return lines;
}
