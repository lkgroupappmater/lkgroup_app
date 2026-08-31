$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$p = Join-Path $root "lib\services\shipment_service.dart"
if (!(Test-Path $p)) { throw "파일 없음: $p" }

Copy-Item $p "$p.bak_before_patch135" -Force
$s = Get-Content $p -Raw -Encoding UTF8

$old = @'
  Future<int> upsertFromRows(List<Map<String, dynamic>> rows) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return 0;
    final payload = rows.map(_shipmentPayload).toList();
    final result = await SupabaseService.client.rpc(
      'manager_upsert_unlocked_shipments',
      params: {'p_rows': payload},
    );
    return (result as num?)?.toInt() ?? 0;
  }
'@

$new = @'
  Future<int> upsertFromRows(List<Map<String, dynamic>> rows) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return 0;

    // 대용량 Excel을 한 번의 RPC로 보내면 PostgreSQL statement_timeout(57014)에
    // 걸릴 수 있으므로 작은 묶음으로 나눠 순차 반영합니다.
    // 각 행의 import_key가 동일하므로 기존 upsert 동작/중복 방지는 그대로 유지됩니다.
    const chunkSize = 40;
    var inserted = 0;

    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = (start + chunkSize < rows.length)
          ? start + chunkSize
          : rows.length;
      final chunk = rows.sublist(start, end);
      inserted += await _upsertShipmentChunk(chunk);
    }

    return inserted;
  }

  Future<int> _upsertShipmentChunk(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return 0;

    final payload = rows.map(_shipmentPayload).toList();

    try {
      final result = await SupabaseService.client.rpc(
        'manager_upsert_unlocked_shipments',
        params: {'p_rows': payload},
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (error) {
      final message = error.toString();

      // DB statement_timeout이면 현재 묶음을 한 번 더 쪼개서 재시도합니다.
      // 최소 5행까지 자동 분할하여 현장 대용량 업로드 성공률을 높입니다.
      final isStatementTimeout =
          message.contains('57014') ||
          message.toLowerCase().contains('statement timeout');

      if (isStatementTimeout && rows.length > 5) {
        final middle = (rows.length / 2).ceil();
        final left = rows.sublist(0, middle);
        final right = rows.sublist(middle);

        final leftCount = await _upsertShipmentChunk(left);
        final rightCount = await _upsertShipmentChunk(right);
        return leftCount + rightCount;
      }

      rethrow;
    }
  }
'@

if (!$s.Contains($old)) {
  throw "shipment_service.dart의 upsertFromRows 원본 블록을 찾지 못했습니다. 파일 변경을 중단합니다."
}
$s = $s.Replace($old,$new)
Set-Content $p $s -Encoding UTF8

Write-Host "[OK] Excel 대용량 업로드 RPC를 40행 단위로 분할" -ForegroundColor Green
Write-Host "[OK] 57014 timeout 발생 시 해당 묶음을 자동 반분 재시도" -ForegroundColor Green
Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
Write-Host "flutter run"
