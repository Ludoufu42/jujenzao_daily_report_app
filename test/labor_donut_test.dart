import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujenzao_daily_report_app/screens/wizard/step_preview.dart';
import 'package:jujenzao_daily_report_app/wizard/report_preview_data.dart';

ReportPreviewData _data(Map<String, double> byCat) => ReportPreviewData(
  calendarDays: 1,
  remainingDays: 1,
  workingDays: null,
  weekdayLabel: '二',
  laborRows: const [],
  materialRows: const [],
  equipmentRows: const [],
  laborByCategory: byCat,
);

void main() {
  // 手機上三個摘要框並排,每個只有約 95px 寬;人員框的圖例不能被擠掉。
  testWidgets('人員框在 95px 寬時顯示總工數與每個類別的工數', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 95,
            child: LaborDonutBox(
              data: _data({'假設工程': 3, '基礎工程': 2.5}),
            ),
          ),
        ),
      ),
    );
    expect(find.text('人員　共 5.5 工'), findsOneWidget);
    expect(find.text('假設工程 3工 55%'), findsOneWidget);
    expect(find.text('基礎工程 2.5工 45%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒有出工時顯示本日無資料', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 95, child: LaborDonutBox(data: _data({}))),
      ),
    );
    expect(find.text('本日無資料'), findsOneWidget);
  });
}
