$ErrorActionPreference = 'Stop'

# ---------- management_menu_screen.dart ----------
$path = "lib/screens/management_menu_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("import 'excel_bulk_management_screen.dart';")) {
  $needle = "import 'excel_export_screen.dart';"
  if (!$text.Contains($needle)) { throw "management menu import anchor not found" }
  $text = $text.Replace($needle, "$needle`r`nimport 'excel_bulk_management_screen.dart';")
}

if (!$text.Contains("'엑셀 데이타 일괄 관리")) {
  $needle = @"
        {
          'label': '화물 내용 변경 승인 관리',
          'icon': Icons.fact_check_outlined,
          'page': const ChangeApprovalScreen(),
        },
"@
  if (!$text.Contains($needle)) { throw "management menu admin item anchor not found" }
  $add = $needle + @"
        {
          'label': '엑셀 데이타 일괄 관리`n(편집 잠금/해제, 구획 및 영수 번호 관리)',
          'icon': Icons.table_view_outlined,
          'page': const ExcelBulkManagementScreen(),
        },
"@
  $text = $text.Replace($needle, $add)
}
Set-Content -Encoding UTF8 -Path $path -Value $text

# ---------- shipment_service.dart ----------
$path = "lib/services/shipment_service.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

$old = @"
  Future<int> upsertFromRows(List<Map<String, dynamic>> rows) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return 0;
    final payload = rows.map(_shipmentPayload).toList();
    await SupabaseService.client
        .from('shipments')
        .upsert(payload, onConflict: 'import_key');
    return payload.length;
  }
"@

$new = @"
  Future<int> upsertFromRows(List<Map<String, dynamic>> rows) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return 0;
    final payload = rows.map(_shipmentPayload).toList();
    final result = await SupabaseService.client.rpc(
      'manager_upsert_unlocked_shipments',
      params: {'p_rows': payload},
    );
    return (result as num?)?.toInt() ?? 0;
  }
"@

if (!$text.Contains("manager_upsert_unlocked_shipments")) {
  if (!$text.Contains($old)) { throw "shipment upsert anchor not found" }
  $text = $text.Replace($old, $new)
}

# Pending requests: admin UI에서 locked 표시를 위해 현재 화물 잠금 상태를 안전하게 보강.
$old2 = @"
  Future<List<Map<String, dynamic>>> getPendingChangeRequests() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.rpc(
      'get_pending_shipment_change_requests',
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }
"@

$new2 = @"
  Future<List<Map<String, dynamic>>> getPendingChangeRequests() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client.rpc(
      'get_pending_shipment_change_requests',
    );
    final rows = List<Map<String, dynamic>>.from(raw as List);

    for (final request in rows) {
      try {
        final route = '\${request['route'] ?? ''}';
        final year = (request['shipment_year'] as num?)?.toInt();
        final voyage = '\${request['voyage'] ?? ''}';
        final box = '\${request['box_number'] ?? ''}';
        if (route.isEmpty || year == null || voyage.isEmpty || box.isEmpty) {
          continue;
        }
        final matches = await SupabaseService.client
            .from('shipments')
            .select('data_locked')
            .eq('route', route)
            .eq('shipment_year', year)
            .eq('voyage', voyage)
            .eq('box_number', box)
            .limit(1);
        if (matches.isNotEmpty) {
          request['data_locked'] = matches.first['data_locked'] == true;
        }
      } catch (_) {
        // 잠금 표시 보강 실패가 기존 승인 요청 조회 자체를 막으면 안 됩니다.
      }
    }
    return rows;
  }
"@

if (!$text.Contains("request['data_locked']")) {
  if (!$text.Contains($old2)) { throw "pending request anchor not found" }
  $text = $text.Replace($old2, $new2)
}
Set-Content -Encoding UTF8 -Path $path -Value $text

# ---------- change_approval_screen.dart ----------
$path = "lib/screens/change_approval_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("데이터 수정 잠금된 화물")) {
  $needle = @"
            const SizedBox(height: 8),
            const Text('요청 내용', style: TextStyle(fontWeight: FontWeight.bold)),
"@
  if (!$text.Contains($needle)) { throw "change approval card anchor not found" }
  $replacement = @"
            if (r['data_locked'] == true) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock, size: 16, color: Colors.redAccent),
                  SizedBox(width: 5),
                  Text(
                    '데이터 수정 잠금된 화물',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text('요청 내용', style: TextStyle(fontWeight: FontWeight.bold)),
"@
  $text = $text.Replace($needle, $replacement)
}
Set-Content -Encoding UTF8 -Path $path -Value $text

Write-Host "PHASE 3A Dart patch complete"
