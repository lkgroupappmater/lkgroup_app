import 'package:flutter_test/flutter_test.dart';
import '../lib/core/document_amounts.dart';
import '../lib/core/money_format.dart';

void main() {
  test('zero-rated invoices win over the tax-invoice keyword in every spacing form', () {
    for (final route in ['kr_la_sea', 'kr_la_air']) {
      for (final remark in ['영세율 세금 계산서', '영세율세금계산서',
          '영 세 율\n세금\t계산서', '영세율\u00a0세금\u3000계산서',
          '세금 계산서 발급 / 영세율 적용']) {
        expect(DocumentAmounts.vatRate(route, remark), 0);
        expect(DocumentAmounts.krwAccount(remark).number, '2070133424601');
        final totals = DocumentAmounts.totals(gross: 1050.54, exempt: 50,
            regular: 200.108, special: 100.054,
            vatRate: DocumentAmounts.vatRate(route, remark));
        expect(totals.vat, 0);
        expect(totals.total, closeTo(750.378, .000001));
      }
      for (final remark in ['세금 계산서', '세금계산서 발급', '세금\n계산서']) {
        expect(DocumentAmounts.vatRate(route, remark), .1);
      }
    }
    expect(DocumentAmounts.vatRate('th_la_land', '세금 계산서'), 0);
    expect(DocumentAmounts.vatRate('kr_la_sea', '일반 고객'), 0);
  });
  test('same inputs match LKS/LKA Excel discounts, VAT and currency rounding', () {
    for (final route in ['kr_la_sea', 'kr_la_air']) {
      final rate = DocumentAmounts.vatRate(route, '카톡 명세서 / 세금 계산서');
      final result = DocumentAmounts.totals(gross: 1050.54, exempt: 50,
          regular: 200.108, special: 100.054, vatRate: rate);
      expect(result.regular, closeTo(200.108, .000001));
      expect(result.special, closeTo(100.054, .000001));
      expect(result.vat, closeTo(75.0378, .000001));
      expect(result.total, closeTo(825.4158, .000001));
      expect(MoneyFormat.documentUsdNumber(result.total), '825.4');
      expect(MoneyFormat.kipNumber(result.total * 22000), '18,160,000');
      expect(MoneyFormat.number(DocumentAmounts.thb(result.total * 31.5)), '26,010');
      expect(MoneyFormat.krwNumber(result.total * 1385), '1,143,300');
      expect(DocumentAmounts.vatRate(route, ''), 0);
    }
  });
  test('100% discounts preserve exempt prepaid delivery and cap special discount', () {
    final result = DocumentAmounts.totals(gross: 120, exempt: 20,
        regular: 100, special: 15, vatRate: .1);
    expect(result.regular, 100);
    expect(result.special, 0);
    expect(result.vat, 2);
    expect(result.total, 22);
    expect(DocumentAmounts.thb(1031.49), 1040);
    expect(DocumentAmounts.thb(1040), 1040);
  });
}
