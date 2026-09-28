import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lkgroup_app/services/excel_upload_transport.dart';

void main() {
  test('temporary storage errors retry the same operation', () async {
    var calls = 0;
    final result = await retryExcelSourceUpload(() async {
      calls++;
      if (calls < 3) throw const StorageException('Temporary unavailable', statusCode: '503');
      return 'same-object';
    }, wait: (_) async {});
    expect(calls, 3);
    expect(result, 'same-object');
  });
  test('permissions and workbook errors stop immediately', () async {
    for (final error in <Object>[
      const StorageException('Forbidden', statusCode: '403'),
      const StorageException('Invalid type', statusCode: '400'),
      const FormatException('Invalid workbook'),
    ]) {
      var calls = 0;
      await expectLater(retryExcelSourceUpload(() async { calls++; throw error; }, wait: (_) async {}), throwsA(same(error)));
      expect(calls, 1);
    }
  });
  test('network retries are bounded', () async {
    var calls = 0;
    await expectLater(retryExcelSourceUpload(() async { calls++; throw TimeoutException('timed out'); }, wait: (_) async {}), throwsStateError);
    expect(calls, 3);
    expect(isRetryableExcelUpload(const StorageException('Failed to fetch')), isTrue);
  });
  test('source object names preserve route and extension without unsafe filename characters', () {
    final a = excelSourceObjectPath('th_la_land', 2026, '00', '5. 태국-라오스.xlsx');
    final b = excelSourceObjectPath('th_la_land', 2026, '00', '5. 태국-라오스.xlsx');
    expect(a, matches(RegExp(r'^th_la_land/2026/V00/[a-f0-9]{32}_5\.___-___.xlsx$')));
    expect(a, isNot(b));
  });
}
