import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/document_amounts.dart';
import 'package:lkgroup_app/services/automation_workbook_rules.dart';

void main() {
  test('tax invoice Remark selects the specified Korean account', () {
    for (final remark in ['세금 계산서 발급', '카톡 명세서 / 세금계산서 발급 / 지방배송', '세금\n계산서\t발급']) {
      expect(DocumentAmounts.krwAccount(remark), (number: '2070133424601', holder: '박성호(엘케이무역)'));
    }
    for (final remark in ['', '일반 고객', '세금 계산서 문의']) {
      expect(DocumentAmounts.krwAccount(remark), (number: '571-22-0330221', holder: '박성호'));
    }
  });
  test('renamed and legacy Remark sheets import the same customer rules', () {
    final rows = [['No', 'Name', 'Tel', '내용'], ['1', 'Remark QA', '020-9999-9999', '세금 계산서 발급']];
    final renamed = AutomationWorkbookRules.shares({'Remark 및 특이사항': rows});
    expect(renamed, AutomationWorkbookRules.shares({'명세서 선공유': rows}));
    expect(renamed!.single['content'], '세금 계산서 발급');
    expect(AutomationWorkbookRules.shares({'명세서 선공유': [['No', 'Name', 'Tel', '내용']], 'Remark 및 특이사항': rows}), renamed);
  });
}
