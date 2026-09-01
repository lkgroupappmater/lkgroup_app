from pathlib import Path
p=Path("lib/services/excel_import_service.dart")
s=p.read_text(encoding="utf-8-sig")

# 1) V00 mode right after route/year/voyage resolution.
anchor = """    final routeKey = meta.$1;
    final routeLabel = RouteCatalog.labelForKey(routeKey);
    final year = meta.$2;
    final voyage = meta.$3;

    final rows = <Map<String, dynamic>>[];"""
replacement = """    final routeKey = meta.$1;
    final routeLabel = RouteCatalog.labelForKey(routeKey);
    final year = meta.$2;
    final voyage = meta.$3;
    final isBaseUpdate = voyage == '00';

    // V00 is NEVER a real shipment voyage.
    // It is a route-wide BASE/policy workbook. Even if a template happens to
    // contain reserved cargo numbers/formulas, V00 must not upsert shipments.
    if (isBaseUpdate) {
      onProgress?.call(0.30, 'V00 BASE 확인 · 실제 화물 데이터는 변경하지 않습니다');
      await _importLocalDeliveryProfiles(bytes, workbook, routeKey: routeKey);

      onProgress?.call(0.45, '시내·지방배송 BASE 반영 완료 · 할인 고객 갱신 중');
      final customerRuleResult =
          await _importCustomerDiscountRules(workbook, routeKey: routeKey);
      await _importStatementShareRules(workbook, routeKey: routeKey);

      if (SupabaseConfig.isConfigured) {
        final rawBatches = await SupabaseService.client.rpc(
          'list_route_shipment_batches',
          params: {'p_route': routeLabel},
        );
        final batches = rawBatches is List
            ? rawBatches
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(growable: false)
            : <Map<String, dynamic>>[];

        for (var i = 0; i < batches.length; i++) {
          final batch = batches[i];
          final batchYear = (batch['shipment_year'] as num?)?.toInt();
          final batchVoyage = '${batch['voyage'] ?? ''}'.trim();
          if (batchYear == null || batchVoyage.isEmpty) continue;

          final fraction = batches.isEmpty ? 1.0 : (i + 1) / batches.length;
          onProgress?.call(
            0.58 + fraction * 0.34,
            '기존 ${batchYear}년 ${batchVoyage}항차 재정비 중 '
            '(${i + 1}/${batches.length})',
          );

          await SupabaseService.client.rpc(
            'admin_finalize_excel_batch_rules_fast',
            params: {
              'p_route': routeLabel,
              'p_year': batchYear,
              'p_voyage': batchVoyage,
              'p_resequence': true,
            },
          );
        }
      }

      onProgress?.call(1.0, 'V00 BASE Update 완료');
      return ExcelImportResult(
        inserted: 0,
        skipped: 0,
        customerRules: customerRuleResult.applied,
        customerRulesWaitingForPhone:
            customerRuleResult.waitingForPhone,
        message:
            'V00 BASE Update 완료: 실제 화물은 추가/삭제/덮어쓰기 하지 않고, '
            '$routeLabel 경로의 배송·할인·선공유 규칙을 갱신한 뒤 기존 항차를 재정비했습니다.',
      );
    }

    final rows = <Map<String, dynamic>>[];"""
if anchor not in s:
    raise SystemExit("V00 insertion anchor not found")
s=s.replace(anchor,replacement,1)

# 2) Fix ON CONFLICT same-row-twice:
#    PostgreSQL can still see duplicates after DB-side normalization even when
#    raw Dart strings differ. Upsert one rule per statement.
old = """    await SupabaseService.client
        .from('customer_rate_overrides')
        .upsert(
          uniqueRules.values.toList(growable: false),
          onConflict: 'customer_name,phone,route_key',
        );

    return (applied: applied, waitingForPhone: waitingForPhone);"""
new = """    // One-row-at-a-time is intentional.
    // DB unique/index normalization may collapse names that look different in
    // Excel (spacing/punctuation/etc.). A multi-row INSERT ... ON CONFLICT can
    // then hit the same target row twice and fail with SQLSTATE 21000.
    for (final rule in uniqueRules.values) {
      await SupabaseService.client
          .from('customer_rate_overrides')
          .upsert(
            rule,
            onConflict: 'customer_name,phone,route_key',
          );
    }

    return (applied: applied, waitingForPhone: waitingForPhone);"""
if old not in s:
    raise SystemExit("discount upsert anchor not found")
s=s.replace(old,new,1)

p.write_text(s,encoding="utf-8")
print("Patch178 applied.")
