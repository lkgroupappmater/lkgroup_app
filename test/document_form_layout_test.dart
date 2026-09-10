import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/document_form_style.dart';
import '../lib/core/document_text_catalog.dart';
import '../lib/core/route_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.otf'))).load();
    await (FontLoader('PhetsarathOT')
      ..addFont(rootBundle.load('assets/fonts/phetsarath_ot.ttf'))).load();
  });

  test('all route quotation and statement notes fit without clipping', () {
    final date = DateTime(2026, 9, 10);
    expect(RouteCatalog.routes.length, 11);
    for (final route in RouteCatalog.routes) {
      for (final content in [DocumentTextCatalog.quotation(route, date),
          DocumentTextCatalog.statement(route, date)]) {
        final layout = DocumentFormLayout(itemCount: 1,
          remark: content.remark, remarkFontSize: content.remarkFontSize,
          footer: content.footerText, footerFontSize: content.footerFontSize);
        final remarkHeight = DocumentFormStyle.textHeight(content.remark,
          content.remarkFontSize, DocumentFormStyle.remarkWidth, lineHeight: 1.2);
        final footerHeight = DocumentFormStyle.textHeight(content.footerText,
          content.footerFontSize, DocumentFormStyle.footerWidth, lineHeight: 1.2);
        expect(remarkHeight, lessThanOrEqualTo(layout.summaryHeight - 54), reason: route);
        expect(footerHeight, lessThanOrEqualTo(layout.signHeight - 24), reason: route);
        expect(layout.paymentTop, greaterThan(layout.summaryTop + layout.summaryHeight));
        expect(layout.height, greaterThan(layout.signTop + layout.signHeight));
      }
    }
  });

  test('long operational remarks and delivery details extend every export', () {
    final remark = List.filled(40, '취급 주의 / 할인 10% 적용 / 지방배송(선결제)').join('\n');
    final delivery = List.filled(25, 'ການຂົນສົ່ງ 배송 주소와 수취인 안내').join('\n');
    final layout = DocumentFormLayout(itemCount: 35,
      remark: remark, remarkFontSize: 19, delivery: delivery,
      footer: List.filled(20, '경로별 운임 및 하단 안내').join('\n'), footerFontSize: 17.5);
    expect(layout.rowCount, 36);
    expect(layout.summaryHeight, greaterThan(190));
    expect(layout.signHeight, greaterThan(112));
    expect(DocumentFormStyle.textHeight(delivery, 18.5,
        DocumentFormStyle.deliveryWidth, bold: true, lineHeight: 1.16),
      lessThanOrEqualTo(layout.summaryHeight - 56));
  });
}
