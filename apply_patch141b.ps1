$ErrorActionPreference = "Stop"
$path = "lib/services/unknown_recipient_service.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }
$src = Get-Content $path -Raw -Encoding UTF8

$old=@'
    final id = int.tryParse(shipmentId);
    if (id == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client.rpc(
      'admin_review_incomplete_shipment',
      params: {
        'p_shipment_id': id,
'@
$new=@'
    final id = shipmentId.trim();
    if (id.isEmpty) throw StateError('화물 ID가 비어 있습니다.');
    await SupabaseService.client.rpc(
      'admin_review_incomplete_shipment',
      params: {
        'p_shipment_id': id,
'@

$count=([regex]::Matches($src,[regex]::Escape($old))).Count
if ($count -ne 1) { throw "안전 중단: reviewIncomplete ID 블록 발견 수=$count" }
$src=$src.Replace($old,$new)
Set-Content $path $src -Encoding UTF8
Write-Host "Patch141b Flutter 적용 완료"
