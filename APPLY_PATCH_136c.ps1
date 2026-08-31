$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$p = Join-Path $root "lib\services\excel_import_service.dart"
if (!(Test-Path $p)) { throw "파일 없음: $p" }

Copy-Item $p "$p.bak_before_patch136c" -Force
$s = Get-Content $p -Raw -Encoding UTF8

# received_at를 DB payload에 넣기 전에 Excel serial date를 ISO 날짜로 변환
$old = @'
          rows.add({
            ...map,
            'route': routeLabel,
'@

$new = @'
          // Excel 날짜 셀은 OOXML에서 2026-07-14 같은 문자열이 아니라
          // 46217 같은 serial number로 저장될 수 있습니다.
          // DB received_at은 timestamptz이므로 업로드 전에 ISO 날짜로 정규화합니다.
          final receivedAtRaw = '${map['received_at'] ?? ''}'.trim();
          if (receivedAtRaw.isNotEmpty) {
            map['received_at'] = _normaliseExcelDateValue(receivedAtRaw);
          }

          rows.add({
            ...map,
            'route': routeLabel,
'@

if (!$s.Contains($old)) {
  throw "excel_import_service.dart: rows.add 위치를 찾지 못했습니다."
}
$s = $s.Replace($old,$new)

$anchor = @'
  static bool _isCustomerNameHeader(String value) {
'@

$helper = @'
  static String _normaliseExcelDateValue(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';

    // 이미 ISO/일반 날짜 문자열이면 그대로 둡니다.
    if (DateTime.tryParse(text) != null) return text;

    // Excel 1900 date system serial.
    // 25569 == 1970-01-01. 소수부가 있으면 시간까지 보존합니다.
    final serial = double.tryParse(text);
    if (serial != null && serial >= 30000 && serial <= 70000) {
      final milliseconds =
          ((serial - 25569) * Duration.millisecondsPerDay).round();
      final date = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
      return date.toIso8601String();
    }

    // 날짜로 해석할 수 없는 값은 그대로 반환하여 기존 동작을 보존합니다.
    return text;
  }

'@

if (!$s.Contains($anchor)) {
  throw "excel_import_service.dart: helper 삽입 위치를 찾지 못했습니다."
}
$s = $s.Replace($anchor,$helper+$anchor)

Set-Content $p $s -Encoding UTF8

Write-Host "[OK] Excel serial 날짜 -> ISO timestamptz 변환 적용" -ForegroundColor Green
Write-Host "[OK] 예: 46217 -> ISO 날짜/시간" -ForegroundColor Green
Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
Write-Host "flutter run"
Write-Host ""
Write-Host "그 후 동일 V08 Excel을 다시 업로드하세요." -ForegroundColor Yellow
