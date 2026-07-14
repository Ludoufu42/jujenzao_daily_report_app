import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/inspection.dart';
import '../models/project.dart';
import 'web_blob_store.dart';

class InspectionPdfService {
  static Future<Uint8List> generate({
    required Project project,
    required String criticalPathLabel,
    required String templateName,
    required List<InspectionItemRecord> items,
    required List<String> photoPaths,
    required Uint8List inspectorSignature,
    required DateTime inspectedAt,
  }) async {
    final font = await PdfGoogleFonts.notoSansTCRegular();
    final boldFont = await PdfGoogleFonts.notoSansTCMedium();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
    );

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final hasDefect = items.any((i) => i.result == InspectionResult.defect);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.bottomRight,
          child: pw.Text(
            '${project.name}/$criticalPathLabel 要徑查驗表',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Text(
            '要徑查驗表',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            height: 3,
            color: const PdfColor.fromInt(0xFF2F6FE0),
          ),
          _headerTable(
            project: project,
            criticalPathLabel: criticalPathLabel,
            templateName: templateName,
            inspectedAt: inspectedAt,
            hasDefect: hasDefect,
            dateFormat: dateFormat,
          ),
          pw.SizedBox(height: 12),
          _checklistTable(items),
          pw.SizedBox(height: 16),
          _signatureRow(inspectorSignature),
          pw.SizedBox(height: 16),
          pw.Text(
            '現場照片',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (photoPaths.isEmpty)
            pw.Text('本次查驗無照片。', style: const pw.TextStyle(color: PdfColors.grey600))
          else
            ...photoPaths.map(
              (path) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Image(pw.MemoryImage(WebBlobStore.readBytes(path))),
              ),
            ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _cell(String label, String value) {
    return pw.Expanded(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 70,
            padding: const pw.EdgeInsets.all(6),
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF0FD)),
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _headerTable({
    required Project project,
    required String criticalPathLabel,
    required String templateName,
    required DateTime inspectedAt,
    required bool hasDefect,
    required DateFormat dateFormat,
  }) {
    pw.Widget row(List<pw.Widget> cells) => pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(children: cells),
    );

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
      child: pw.Column(
        children: [
          row([_cell('工程名稱', project.name), _cell('公司名稱', project.companyName)]),
          row([_cell('查驗要徑', criticalPathLabel), _cell('檢查表', templateName)]),
          row([
            _cell('查驗時間', dateFormat.format(inspectedAt)),
            _cell('查驗結果', hasDefect ? '有缺失項目' : '全數合格'),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _checklistTable(List<InspectionItemRecord> items) {
    pw.Widget headerCell(String text) => pw.Container(
      padding: const pw.EdgeInsets.all(4),
      color: const PdfColor.fromInt(0xFFEAF0FD),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );
    pw.Widget dataCell(String text, {PdfColor? color}) => pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, color: color)),
    );

    final rows = <pw.TableRow>[
      pw.TableRow(children: [headerCell('檢查項目'), headerCell('查驗重點'), headerCell('檢查結果')]),
    ];
    for (final item in items) {
      final isDefect = item.result == InspectionResult.defect;
      rows.add(
        pw.TableRow(
          children: [
            dataCell(item.itemName),
            dataCell(item.description),
            dataCell(
              item.result.label,
              color: isDefect ? PdfColors.red : const PdfColor.fromInt(0xFF2F6B52),
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FlexColumnWidth(0.8),
      },
      children: rows,
    );
  }

  static pw.Widget _signatureRow(Uint8List signature) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Row(
        children: [
          pw.Text('查驗人員簽名', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 12),
          pw.Container(height: 50, width: 120, child: pw.Image(pw.MemoryImage(signature))),
        ],
      ),
    );
  }
}
