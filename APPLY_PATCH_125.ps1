$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Copy-PatchFile($srcRel,$dstRel) {
  $src=Join-Path $Root $srcRel
  $dst=Join-Path $Root $dstRel
  if (!(Test-Path $src)) { throw "패치 파일 없음: $src" }
  $dir=Split-Path $dst -Parent
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (Test-Path $dst) { Copy-Item $dst "$dst.bak_before_patch125" -Force }
  Copy-Item $src $dst -Force
}
Copy-PatchFile "patch_files\lib\services\settlement_snapshot_service.dart" "lib\services\settlement_snapshot_service.dart"
Copy-PatchFile "patch_files\supabase\069_voyage_settlement_snapshots.sql" "supabase\069_voyage_settlement_snapshots.sql"

# Voyage total 화면: 계산 성공 시 동일 settlement을 snapshot 저장.
$screen=Join-Path $Root "lib\screens\voyage_total_management_screen.dart"
if (!(Test-Path $screen)) { throw "Patch124 화면 파일 없음: $screen" }
Copy-Item $screen "$screen.bak_before_patch125" -Force
$text=Get-Content $screen -Raw -Encoding UTF8

if ($text -notmatch "settlement_snapshot_service.dart") {
  $text=$text.Replace(
    "import '../services/receipt_settlement_service.dart';",
    "import '../services/receipt_settlement_service.dart';`r`nimport '../services/settlement_snapshot_service.dart';"
  )
}

$old=@'
      final result =
          await ReceiptSettlementService.instance.calculate(rows);
      if (!mounted) return;
      setState(() => _settlement = result);
'@
$new=@'
      final result =
          await ReceiptSettlementService.instance.calculate(rows);
      await SettlementSnapshotService.instance.save(
        routeKey: _route!,
        routeLabel: _route!,
        year: _year!,
        voyage: _voyage!,
        settlement: result,
      );
      if (!mounted) return;
      setState(() => _settlement = result);
'@
if ($text.Contains($old)) {
  $text=$text.Replace($old,$new)
} elseif ($text -notmatch "SettlementSnapshotService.instance.save") {
  throw "항차 정산 snapshot 삽입 위치를 찾지 못했습니다."
}
Set-Content $screen $text -Encoding UTF8

# Excel export: export 직전에 현재 DB 화물로 Receipt Settlement 계산 + snapshot 갱신.
$export=Join-Path $Root "lib\services\excel_export_service.dart"
if (!(Test-Path $export)) { throw "Excel export service 없음: $export" }
Copy-Item $export "$export.bak_before_patch125" -Force
$e=Get-Content $export -Raw -Encoding UTF8

if ($e -notmatch "excel_bulk_management_service.dart") {
  $e=$e.Replace(
    "import 'supabase_service.dart';",
    "import 'supabase_service.dart';`r`nimport 'excel_bulk_management_service.dart';`r`nimport 'receipt_settlement_service.dart';`r`nimport 'settlement_snapshot_service.dart';"
  )
}

$needle=@'
    final response = await SupabaseService.client.functions.invoke(
      'export-shipment-excel',
'@
$insert=@'
    // Excel 생성 직전 DB의 현재 화물을 중앙 FreightService로 영수번호별 정산하고
    // 동일 결과를 snapshot으로 저장합니다. Edge Function은 다음 단계부터 이 snapshot을
    // Row data에 그대로 사용하므로 Excel용 별도 운임 계산식을 만들지 않습니다.
    final settlementRows =
        await ExcelBulkManagementService.instance.listRows(
      route: batch.routeLabel,
      year: batch.year,
      voyage: batch.voyage,
    );
    final settlement =
        await ReceiptSettlementService.instance.calculate(settlementRows);
    await SettlementSnapshotService.instance.save(
      routeKey: batch.routeKey,
      routeLabel: batch.routeLabel,
      year: batch.year,
      voyage: batch.voyage,
      settlement: settlement,
    );

    final response = await SupabaseService.client.functions.invoke(
      'export-shipment-excel',
'@
if ($e.Contains($needle)) {
  $e=$e.Replace($needle,$insert)
} elseif ($e -notmatch "final settlementRows") {
  throw "Excel export snapshot 삽입 위치를 찾지 못했습니다."
}
Set-Content $export $e -Encoding UTF8

Write-Host "Patch125 적용 완료."
Write-Host "다음:"
Write-Host "1) Supabase SQL Editor에서 supabase/069_voyage_settlement_snapshots.sql 전체 실행"
Write-Host "2) flutter analyze"
