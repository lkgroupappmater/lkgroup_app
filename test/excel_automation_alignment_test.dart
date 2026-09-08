import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/services/customer_benefit_service.dart';
import 'package:lkgroup_app/services/excel_file_metadata.dart';
import 'package:lkgroup_app/services/shipment_service.dart';

void main() {
  group('ExcelFileMetadataParser', () {
    test('accepts the canonical xlsx name', () {
      final meta = ExcelFileMetadataParser.tryParse(
        'KR_LA_SEA_2026_V08_SHIPMENTS.xlsx',
      );
      expect(meta?.routeKey, 'kr_la_sea');
      expect(meta?.year, 2026);
      expect(meta?.voyage, '08');
    });

    test('accepts a descriptive LKS xlsm name', () {
      final meta = ExcelFileMetadataParser.tryParse(
        '1. Kor-Lao Sea LKS 2026 08항차 최종본.xlsm',
      );
      expect(meta?.routeKey, 'kr_la_sea');
      expect(meta?.year, 2026);
      expect(meta?.voyage, '08');
    });

    test('accepts an LKA air workbook', () {
      final meta = ExcelFileMetadataParser.tryParse(
        '한국-라오스 항공 LKA_2026_V12_수정.xlsm',
      );
      expect(meta?.routeKey, 'kr_la_air');
      expect(meta?.year, 2026);
      expect(meta?.voyage, '12');
    });

    test('treats an explicit xx voyage as the V00 BASE policy file', () {
      final meta = ExcelFileMetadataParser.tryParse(
        '1. Kor-Lao Sea 한국-라오스 해상 xx항차 거래명세서_2026xxxx.xlsm',
      );
      expect(meta?.routeKey, 'kr_la_sea');
      expect(meta?.year, 2026);
      expect(meta?.voyage, '00');
    });

    test('accepts arbitrary descriptive text after the canonical V00 prefix', () {
      final meta = ExcelFileMetadataParser.tryParse(
        'KR_LA_SEA_2026_V00_기준명세서_수정본.xlsm',
      );
      expect(meta?.routeKey, 'kr_la_sea');
      expect(meta?.year, 2026);
      expect(meta?.voyage, '00');
    });

    test('rejects a name without a voyage token', () {
      expect(
        ExcelFileMetadataParser.tryParse('LKS_2026_최종본.xlsx'),
        isNull,
      );
    });
  });

  group('LocalDeliveryRule', () {
    const rule = LocalDeliveryRule(
      id: 1,
      routeKey: 'kr_la_sea',
      sourceNo: 10007,
      customerName: '테스트 고객',
      alternateName: 'Receiver Name',
      companyName: '',
      phone: '02055556666',
      phoneDisplay: '020 5555 6666',
      deliveryType: 'city',
      localCompany: 'HAL',
      destinationAddress: 'Vientiane',
      paidBy: '선결제',
      notes: '',
      active: true,
      preferred: true,
    );

    test('prints values only, with the visible city row number', () {
      expect(
        rule.toStatementText(),
        'No. 7\nReceiver Name\n020 5555 6666\nHAL\nVientiane',
      );
    });

    test('recognizes prepaid spelling variants', () {
      expect(rule.isPrepaid, isTrue);
    });

    LocalDeliveryRule delivery({
      required int no,
      required String name,
      required String phone,
      String paidBy = '',
    }) => LocalDeliveryRule(
          id: no,
          routeKey: 'kr_la_sea',
          sourceNo: no,
          customerName: name,
          alternateName: '',
          companyName: '',
          phone: phone,
          phoneDisplay: phone,
          deliveryType: 'province',
          localCompany: 'HAL',
          destinationAddress: 'Laos',
          paidBy: paidBy,
          notes: '',
          active: true,
          preferred: true,
        );

    test('does not partially match a multi-name delivery profile', () {
      final selected = CustomerBenefitService.selectLocalDeliveryRule(
        rules: [
          delivery(
            no: 68,
            name: '김민규/Shuana lor',
            phone: '02078291765',
          ),
        ],
        name: '김민규',
        phone: '02055599055',
      );
      expect(selected, isNull);
    });

    test('uses a unique phone when the written name is different', () {
      final selected = CustomerBenefitService.selectLocalDeliveryRule(
        rules: [
          delivery(
            no: 48,
            name: '방비엥 고향식당',
            phone: '02091120020',
          ),
        ],
        name: '다른 표기 이름',
        phone: '020 9112 0020',
      );
      expect(selected?.sourceNo, 48);
    });

    test('unknown prefix is ignored only while matching delivery', () {
      final selected = CustomerBenefitService.selectLocalDeliveryRule(
        rules: [
          delivery(no: 22, name: '이우용', phone: '02058477710'),
          delivery(
            no: 23,
            name: '김병찬/이우용',
            phone: '02058477710',
            paidBy: '선결제',
          ),
        ],
        name: '수취인 불명 / 이우용',
        phone: '020 5847 7710 / ???',
      );
      expect(selected?.sourceNo, 22);
      expect(
        CustomerBenefitService.deliveryMatchName('수취인 불명 / 이우용'),
        '이우용',
      );
    });

    test('exact multi-name wins when profiles share a phone', () {
      final selected = CustomerBenefitService.selectLocalDeliveryRule(
        rules: [
          delivery(no: 34, name: '백종훈', phone: '02055854057'),
          delivery(
            no: 87,
            name: '조미숙/백종훈',
            phone: '02055854057',
            paidBy: '선결제',
          ),
        ],
        name: '조미숙 / 백종훈',
        phone: '020-5585-4057 / ????',
      );
      expect(selected?.sourceNo, 87);
      expect(selected?.isPrepaid, isTrue);
    });
  });

  group('ShipmentImportSummary', () {
    test('parses and combines new, identical, and review counts', () {
      final first = ShipmentImportSummary.fromRpc({
        'new_rows': 2,
        'unchanged': 3,
        'change_requests': 4,
        'already_pending': 1,
        'protected_rows': 1,
      });
      const second = ShipmentImportSummary(newRows: 1, unchanged: 2);
      final combined = first + second;

      expect(combined.newRows, 3);
      expect(combined.unchanged, 5);
      expect(combined.changeRequests, 4);
      expect(combined.existingRows, 11);
      expect(combined.actions, 7);
    });
  });
}
