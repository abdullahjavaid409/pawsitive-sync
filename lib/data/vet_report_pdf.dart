import 'dart:typed_data';

import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a vet-ready PDF from [PetReport] data.
Future<Uint8List> buildVetReportPdf({
  required Pet pet,
  required PetReport report,
  required String plainText,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => [
        pw.Text(
          '${pet.name} · care report',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          plainText,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Sent from Pawsitive',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return doc.save();
}
