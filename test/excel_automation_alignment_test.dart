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
