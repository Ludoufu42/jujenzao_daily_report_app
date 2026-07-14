import 'package:flutter_test/flutter_test.dart';

import 'package:jujenzao_daily_report_app/models/inspection_checklist.dart';

void main() {
  test('column and wall rebar share the same template', () {
    final columnTemplate = templateForWorkItem('柱鋼筋組立');
    final wallTemplate = templateForWorkItem('牆鋼筋組立');
    expect(columnTemplate, isNotNull);
    expect(columnTemplate!.templateName, '柱牆鋼筋組立');
    expect(wallTemplate!.templateName, '柱牆鋼筋組立');
  });

  test('每個提供的範本至少有一個檢查項目', () {
    for (final template in kInspectionTemplatesBySecondHalf.values) {
      expect(template.items, isNotEmpty, reason: template.templateName);
    }
  });

  test('外模組立 has no checklist (inspection not required)', () {
    expect(templateForWorkItem('外模組立'), isNull);
  });

  test('假設工程/基礎工程 fixed items have no checklist yet', () {
    expect(templateForWorkItem('圍籬施作'), isNull);
    expect(templateForWorkItem('大底灌漿'), isNull);
  });
}
