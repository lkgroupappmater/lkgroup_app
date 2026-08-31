from pathlib import Path
import sys

root = Path.cwd()
import_file = root / "lib" / "services" / "excel_import_service.dart"
cargo_file = root / "lib" / "screens" / "cargo_management_screen.dart"

for p in (import_file, cargo_file):
    if not p.exists():
        raise SystemExit(f"Required file not found: {p}")

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {count}. No files changed.")
    return text.replace(old, new, 1)

import_text = import_file.read_text(encoding="utf-8-sig")
cargo_text = cargo_file.read_text(encoding="utf-8-sig")

# 1) Delivery profiles must be imported BEFORE shipment upsert, so batch normalization
# can match the current BASE Excel delivery table immediately.
old_flow = """    onProgress?.call(0.45, '중복 정리 완료 · 화물 DB 반영 중');
    final inserted = await ShipmentService.instance.upsertFromRows(uniqueRows);
    onProgress?.call(0.72, '화물 DB 반영 완료 · 고객 규칙 확인 중');
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);
    await _importLocalDeliveryProfiles(bytes, workbook, routeKey: routeKey);
    onProgress?.call(0.86, '고객 규칙 확인 완료 · 원본 Excel 보관 중');
"""
new_flow = """    // Patch167: current BASE Excel delivery table is the source of truth.
    // Import it before shipment upsert so normalize/finalize can see city/province
    // delivery + prepaid + company/address for this very upload.
    onProgress?.call(0.38, '시내·지방 배송표 DB 반영 중');
    await _importLocalDeliveryProfiles(bytes, workbook, routeKey: routeKey);

    onProgress?.call(0.45, '배송표 반영 완료 · 화물 DB 반영 중');
    final inserted = await ShipmentService.instance.upsertFromRows(uniqueRows);
    onProgress?.call(0.72, '화물 DB 반영 완료 · 고객 규칙 확인 중');
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);

    // One batch-scoped finalizer after all rows/rules are ready.
    // Do not silently finish an upload with missing delivery/receipt/zone data.
    if (SupabaseConfig.isConfigured) {
      onProgress?.call(0.82, '배송·구획·영수번호 최종 정리 중');
      await SupabaseService.client.rpc(
        'admin_finalize_excel_batch_rules',
        params: {
          'p_route': routeLabel,
          'p_year': year,
          'p_voyage': voyage,
        },
      );
    }

    onProgress?.call(0.86, '최종 규칙 반영 완료 · 원본 Excel 보관 중');
"""
import_text = replace_once(import_text, old_flow, new_flow, "Patch167 import flow")

# 2) Remove global refresh after every delivery-table import.
old_refresh = """    try {
      await SupabaseService.client.rpc('admin_refresh_shipment_special_notes');
    } catch (_) {
      // 배송표 저장 자체는 기존 특이사항 재계산 실패 때문에 막지 않습니다.
    }
    return bySourceNo.length;
"""
new_refresh = """    // Patch167: do not run a global shipment refresh here.
    // importBytes() runs one batch-scoped finalizer after shipment upsert.
    return bySourceNo.length;
"""
import_text = replace_once(import_text, old_refresh, new_refresh, "Patch167 remove global refresh")

# 3) Add delivery badge variables to receipt group card.
old_vars = """    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    final zone = '${first['unloading_zone'] ?? ''}'.trim();
    final name = '${first['consignee_name'] ?? ''}'.trim();
"""
new_vars = """    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    final zone = '${first['unloading_zone'] ?? ''}'.trim();
    final specialNote = '${first['special_note_auto'] ?? ''}'.trim();
    final deliveryLabel = const <String>[
      '지방배송(선결제)',
      '지방배송',
      '시내배송(선결제)',
      '시내배송',
    ].firstWhere(
      (label) => specialNote.contains(label),
      orElse: () => '',
    );
    final deliveryColor = switch (deliveryLabel) {
      '지방배송(선결제)' => const Color(0xFF5B9BD5),
      '지방배송' => const Color(0xFFFFC000),
      '시내배송(선결제)' => const Color(0xFFFFFF00),
      '시내배송' => const Color(0xFF92D050),
      _ => Colors.transparent,
    };
    final name = '${first['consignee_name'] ?? ''}'.trim();
"""
cargo_text = replace_once(cargo_text, old_vars, new_vars, "Patch167 delivery badge vars")

# 4) Add compact colored badge next to receipt/zone information.
anchor = """                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '총 개수: ',
"""
badge = """                      if (deliveryLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: deliveryColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: .12),
                            ),
                          ),
                          child: Text(
                            deliveryLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '총 개수: ',
"""
cargo_text = replace_once(cargo_text, anchor, badge, "Patch167 delivery badge widget")

# Write only after every validation/replacement succeeded.
import_file.write_text(import_text, encoding="utf-8")
cargo_file.write_text(cargo_text, encoding="utf-8")

print("Patch167 applied:")
print(" - delivery table imported before shipment upsert")
print(" - one batch-scoped finalizer after import")
print(" - removed global refresh from delivery-table import")
print(" - added colored delivery badge to cargo receipt cards")
