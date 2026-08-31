$ErrorActionPreference = "Stop"
$path = "lib/screens/change_approval_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$src = Get-Content $path -Raw -Encoding UTF8

$old1 = @'
          shipmentId: '${row['id']}',
'@
$new1 = @'
          shipmentId: '${row['shipment_id'] ?? row['id'] ?? ''}',
'@

$count1 = ([regex]::Matches($src, [regex]::Escape($old1))).Count
if ($count1 -ne 1) {
  throw "안전 중단: shipmentId 대상 블록 발견 수=$count1"
}
$src = $src.Replace($old1, $new1)

$old2 = @'
                '${row['reason'] ?? '수취인 정보 확인 필요'}',
'@
$new2 = @'
                '${row['uncertainty_reason'] ?? row['reason'] ?? '수취인 정보 확인 필요'}',
'@

$count2 = ([regex]::Matches($src, [regex]::Escape($old2))).Count
if ($count2 -ne 1) {
  throw "안전 중단: reason 대상 블록 발견 수=$count2"
}
$src = $src.Replace($old2, $new2)

Set-Content $path $src -Encoding UTF8
Write-Host "Patch141c 적용 완료: shipment_id / uncertainty_reason 실제 RPC 필드명 연동"
