import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/weather.dart';
import '../wizard/report_draft.dart';
import '../wizard/report_preview_data.dart';
import 'web_blob_store.dart';

const _chartColors = [
  PdfColor.fromInt(0xFF2F6B52),
  PdfColor.fromInt(0xFF639922),
  PdfColor.fromInt(0xFF378ADD),
  PdfColor.fromInt(0xFFBA7517),
  PdfColor.fromInt(0xFFD4537E),
];

class PdfService {
  static Future<Uint8List> generate({
    required ReportDraft draft,
    required ReportPreviewData data,
    required List<String> photoPaths,
    Uint8List? supervisorSignature,
  }) async {
    final font = await PdfGoogleFonts.notoSansTCRegular();
    final boldFont = await PdfGoogleFonts.notoSansTCMedium();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: boldFont),
    );

    final dateFormat = DateFormat('yyyy-MM-dd');
    final project = draft.project;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: draft.isBackfillEntry ? (context) => _backfillStamp() : null,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.bottomRight,
          child: pw.Text(
            '${project.name}/${dateFormat.format(draft.reportDate)}工程日報表',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Text(
            '營建工程管理日報表',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            height: 3,
            color: const PdfColor.fromInt(0xFF2F6B52),
          ),
          _headerTable(project, draft, data, dateFormat),
          pw.SizedBox(height: 10),
          _todayEntrySummary(data),
          pw.SizedBox(height: 10),
          _signatureRow(supervisorSignature),
          pw.NewPage(),
          pw.Text(
            '人員、材料、機具進場紀錄',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _detailTable(data),
          pw.SizedBox(height: 16),
          pw.Text(
            '現場照片',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (photoPaths.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.grey400,
                  style: pw.BorderStyle.dashed,
                ),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                '本日無照片。',
                style: const pw.TextStyle(color: PdfColors.grey600),
              ),
            )
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

  static pw.Widget _backfillStamp() {
    return pw.Align(
      alignment: pw.Alignment.topRight,
      child: pw.Transform.rotate(
        angle: -0.3,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.red, width: 2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            '補登',
            style: pw.TextStyle(
              color: PdfColors.red,
              fontWeight: pw.FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _cell(String label, String value, {bool bold = false}) {
    return pw.Expanded(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 70,
            padding: const pw.EdgeInsets.all(6),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFEFECE3),
            ),
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _row(List<pw.Widget> cells) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(children: cells),
    );
  }

  static pw.Widget _headerTable(
    dynamic project,
    ReportDraft draft,
    ReportPreviewData data,
    DateFormat dateFormat,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        children: [
          _row([
            _cell('專案名稱', project.name),
            _cell('公司名稱', project.companyName),
          ]),
          _row([
            _cell('天氣', '上午：${draft.weatherAm.label}'),
            _cell('', '下午：${draft.weatherPm.label}'),
          ]),
          _row([
            _cell('日期類別', data.weekdayLabel),
            _cell('日報日期', dateFormat.format(draft.reportDate)),
          ]),
          _row([
            _cell('開工日期', dateFormat.format(project.startDate)),
            _cell('竣工日期', dateFormat.format(project.plannedCompletionDate)),
          ]),
          _row([
            _cell('日曆天數', '${data.calendarDays}天'),
            _cell('剩餘天數', '${data.remainingDays}天'),
          ]),
          if (data.workingDays != null)
            _row([
              _cell('工作天數', '${data.workingDays}天'),
              pw.Expanded(child: pw.SizedBox()),
            ]),
          _row([
            _cell('今日進度', draft.todayProgress),
            pw.Expanded(child: pw.SizedBox()),
          ]),
          _row([
            _cell('明日進度', draft.tomorrowProgress),
            pw.Expanded(child: pw.SizedBox()),
          ]),
          _row([_cell('備註', draft.notes), pw.Expanded(child: pw.SizedBox())]),
        ],
      ),
    );
  }

  static pw.Widget _todayEntrySummary(ReportPreviewData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _laborDonutColumn(data)),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _summaryTextColumn(
            '營建材料',
            data.materialRows.isEmpty ? '本日無資料' : null,
            data.materialRows
                .map(
                  (r) => '${r.tradeType.name} ${r.quantity}${r.tradeType.unit}',
                )
                .toList(),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _summaryTextColumn(
            '機具設備',
            data.equipmentRows.isEmpty ? '本日無資料' : null,
            data.equipmentRows
                .map(
                  (r) => '${r.tradeType.name} ${r.quantity}${r.tradeType.unit}',
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _summaryTextColumn(
    String title,
    String? emptyText,
    List<String> lines,
  ) {
    return pw.Container(
      height: 160,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (emptyText != null)
            pw.Text(
              emptyText,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else
            ...lines.map(
              (l) => pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
            ),
        ],
      ),
    );
  }

  static pw.Widget _laborDonutColumn(ReportPreviewData data) {
    final entries = data.laborByCategory.entries.toList();
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return pw.Container(
      height: 160,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '人員',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          if (total <= 0)
            pw.Text(
              '本日無資料',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else ...[
            pw.SizedBox(
              height: 70,
              child: pw.Center(
                child: pw.CustomPaint(
                  size: const PdfPoint(70, 70),
                  painter: (canvas, size) =>
                      _paintDonut(canvas, size, entries, total),
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            ...entries.asMap().entries.map((e) {
              final color = _chartColors[e.key % _chartColors.length];
              final pct = (e.value.value / total * 100).round();
              return pw.Row(
                children: [
                  pw.Container(width: 8, height: 8, color: color),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: pw.Text(
                      '${e.value.key} $pct%',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  static void _paintDonut(
    PdfGraphics canvas,
    PdfPoint size,
    List<MapEntry<String, double>> entries,
    double total,
  ) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final radius = size.x / 2;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < entries.length; i++) {
      final sweep = entries[i].value / total * 2 * math.pi;
      final color = _chartColors[i % _chartColors.length];
      canvas
        ..setColor(color)
        ..moveTo(cx, cy)
        ..lineTo(
          cx + radius * math.cos(startAngle),
          cy + radius * math.sin(startAngle),
        );
      const steps = 40;
      for (var s = 0; s <= steps; s++) {
        final a = startAngle + sweep * s / steps;
        canvas.lineTo(cx + radius * math.cos(a), cy + radius * math.sin(a));
      }
      canvas
        ..lineTo(cx, cy)
        ..fillPath();
      startAngle += sweep;
    }

    canvas
      ..setColor(PdfColors.white)
      ..drawEllipse(cx, cy, radius * 0.45, radius * 0.45)
      ..fillPath();
  }

  static pw.Widget _signatureRow(Uint8List? supervisorSignature) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Row(
        children: [
          pw.Text(
            '工地主任',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(width: 12),
          if (supervisorSignature != null)
            pw.Container(
              height: 50,
              width: 120,
              child: pw.Image(pw.MemoryImage(supervisorSignature)),
            )
          else
            pw.Container(width: 120, height: 1, color: PdfColors.grey600),
        ],
      ),
    );
  }

  static pw.Widget _detailTable(ReportPreviewData data) {
    final headers = [
      '大項',
      '項目',
      '單位',
      '上午',
      '下午',
      '本日合計',
      '累計',
      '代工',
      '廠商',
      '今日工作內容/使用位置',
      '明日工作內容',
    ];

    pw.Widget headerCell(String text) => pw.Container(
      padding: const pw.EdgeInsets.all(4),
      color: const PdfColor.fromInt(0xFFEFECE3),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );

    pw.Widget dataCell(String text) => pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );

    final rows = <pw.TableRow>[
      pw.TableRow(children: headers.map(headerCell).toList()),
    ];

    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    for (final r in data.laborRows) {
      rows.add(
        pw.TableRow(
          children: [
            dataCell(r.tradeType.category),
            dataCell(r.tradeType.name),
            dataCell(r.tradeType.unit),
            dataCell(fmt(r.morning)),
            dataCell(fmt(r.afternoon)),
            dataCell(fmt(r.todayTotal)),
            dataCell(fmt(r.cumulative)),
            dataCell(r.isSubcontracted ? '■' : ''),
            dataCell(r.vendor),
            dataCell(r.todayContent),
            dataCell(r.tomorrowContent),
          ],
        ),
      );
    }
    for (final r in data.materialRows) {
      rows.add(
        pw.TableRow(
          children: [
            dataCell(r.tradeType.category),
            dataCell(r.tradeType.name),
            dataCell(r.tradeType.unit),
            dataCell(''),
            dataCell(''),
            dataCell(fmt(r.quantity)),
            dataCell(fmt(r.cumulative)),
            dataCell(''),
            dataCell(''),
            dataCell(r.usageLocation),
            dataCell(''),
          ],
        ),
      );
    }
    for (final r in data.equipmentRows) {
      rows.add(
        pw.TableRow(
          children: [
            dataCell(r.tradeType.category),
            dataCell(r.tradeType.name),
            dataCell(r.tradeType.unit),
            dataCell(''),
            dataCell(''),
            dataCell(fmt(r.quantity)),
            dataCell(fmt(r.cumulative)),
            dataCell(r.isSubcontracted ? '■' : ''),
            dataCell(r.vendor),
            dataCell(r.todayContent),
            dataCell(r.tomorrowContent),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(0.7),
        3: pw.FlexColumnWidth(0.7),
        4: pw.FlexColumnWidth(0.7),
        5: pw.FlexColumnWidth(0.9),
        6: pw.FlexColumnWidth(0.9),
        7: pw.FlexColumnWidth(0.6),
        8: pw.FlexColumnWidth(1.1),
        9: pw.FlexColumnWidth(1.8),
        10: pw.FlexColumnWidth(1.8),
      },
      children: rows,
    );
  }
}
