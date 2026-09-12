import 'package:flutter_test/flutter_test.dart';
import '../lib/core/document_delivery_style.dart';

void main() {
  test('the four delivery types retain the workbook colors', () {
    expect(DocumentDeliveryStyle.fromProfile('province', prepaid: false), DocumentDeliveryStyle.province);
    expect(DocumentDeliveryStyle.fromProfile('city', prepaid: false), DocumentDeliveryStyle.city);
    expect(DocumentDeliveryStyle.fromProfile('province', prepaid: true), DocumentDeliveryStyle.provincePrepaid);
    expect(DocumentDeliveryStyle.fromProfile('city', prepaid: true), DocumentDeliveryStyle.cityPrepaid);
    expect(DocumentDeliveryStyle.fromProfile('unknown', prepaid: true), isNull);
  });
  test('legacy spacing and prepaid spelling do not lose their color', () {
    for (final note in ['지방배송(선결제)', '지방 배송 (선결재)', '지방배송 선불', 'Province delivery (prepaid)']) {
      expect(DocumentDeliveryStyle.fromNotes([note]), DocumentDeliveryStyle.provincePrepaid, reason: note);
    }
    for (final note in ['시내배송(선결제)', '시내 배송 (선결재)', '시내배송 선불', 'City delivery (pay in advance)']) {
      expect(DocumentDeliveryStyle.fromNotes([note]), DocumentDeliveryStyle.cityPrepaid, reason: note);
    }
    expect(DocumentDeliveryStyle.fromNotes(['지방 배송']), DocumentDeliveryStyle.province);
    expect(DocumentDeliveryStyle.fromNotes(['시내 배송']), DocumentDeliveryStyle.city);
    expect(DocumentDeliveryStyle.fromNotes(['시내배송 / 별도 통관 선불']), DocumentDeliveryStyle.city);
    expect(DocumentDeliveryStyle.fromNotes(['', '기타 안내']), isNull);
  });
}
