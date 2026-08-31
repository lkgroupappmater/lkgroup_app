$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$excel = Join-Path $root "lib\services\excel_import_service.dart"
$screen = Join-Path $root "lib\screens\excel_upload_screen.dart"
$queue = Join-Path $root "lib\services\excel_import_queue_service.dart"

if (!(Test-Path $excel)) { throw "파일 없음: $excel" }

Copy-Item $excel "$excel.bak_before_patch137" -Force
if (Test-Path $screen) { Copy-Item $screen "$screen.bak_before_patch137" -Force }

$s = Get-Content $excel -Raw -Encoding UTF8

# 1) 화물 payload 자체 중복 제거
$oldInserted = @'
    final inserted = await ShipmentService.instance.upsertFromRows(rows);
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);
'@

$newInserted = @'
    // 같은 Excel 안에 동일 import_key가 중복되어 있으면 PostgreSQL
    // ON CONFLICT DO UPDATE가 같은 row를 한 statement에서 두 번 갱신하려다
    // SQLSTATE 21000으로 실패할 수 있습니다.
    // 실제 DB 반영 전 import_key 기준으로 마지막 행 하나만 남깁니다.
    final uniqueRowsByImportKey = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final key = '${row['import_key'] ?? ''}'.trim();
      if (key.isEmpty) continue;
      uniqueRowsByImportKey[key] = row;
    }
    final uniqueRows = uniqueRowsByImportKey.values.toList(growable: false);

    final inserted = await ShipmentService.instance.upsertFromRows(uniqueRows);
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);
'@

if (!$s.Contains($oldInserted)) {
  throw "excel_import_service.dart: inserted 처리 블록을 찾지 못했습니다."
}
$s = $s.Replace($oldInserted,$newInserted)

# 2) 할인 rule도 같은 onConflict key 중복 제거
$oldRules = @'
    await SupabaseService.client
        .from('customer_rate_overrides')
        .upsert(rules, onConflict: 'customer_name,phone,route_key');

    return (applied: applied, waitingForPhone: waitingForPhone);
'@

$newRules = @'
    // Row data 안에서 같은 고객이 여러 할인 목록에 반복 등장할 수 있습니다.
    // 같은 customer_name + phone + route_key를 한 upsert statement에
    // 두 번 넣지 않도록 마지막 항목 하나만 남깁니다.
    final uniqueRules = <String, Map<String, dynamic>>{};
    for (final rule in rules) {
      final key =
          '${rule['customer_name'] ?? ''}|${rule['phone'] ?? ''}|${rule['route_key'] ?? ''}';
      uniqueRules[key] = rule;
    }

    await SupabaseService.client
        .from('customer_rate_overrides')
        .upsert(
          uniqueRules.values.toList(growable: false),
          onConflict: 'customer_name,phone,route_key',
        );

    return (applied: applied, waitingForPhone: waitingForPhone);
'@

if (!$s.Contains($oldRules)) {
  throw "excel_import_service.dart: customer_rate_overrides upsert 블록을 찾지 못했습니다."
}
$s = $s.Replace($oldRules,$newRules)

Set-Content $excel $s -Encoding UTF8

# 3) 큐 서비스 / 화면 교체
Copy-Item (Join-Path $root "patch_files\lib\services\excel_import_queue_service.dart") $queue -Force
Copy-Item (Join-Path $root "patch_files\lib\screens\excel_upload_screen.dart") $screen -Force

Write-Host "[OK] SQLSTATE 21000: 화물 import_key 중복 제거" -ForegroundColor Green
Write-Host "[OK] SQLSTATE 21000: 고객 할인 rule onConflict 중복 제거" -ForegroundColor Green
Write-Host "[OK] Excel 업로드 인앱 작업 Queue 추가" -ForegroundColor Green
Write-Host "[OK] 업로드 화면을 나가도 앱이 켜져 있는 동안 순차 처리" -ForegroundColor Green
Write-Host "[OK] 처리 중에도 다음 Excel을 계속 추가 가능" -ForegroundColor Green
Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
Write-Host "flutter run"
