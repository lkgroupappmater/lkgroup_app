$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$p = Join-Path $root "lib\services\excel_import_service.dart"
if (!(Test-Path $p)) { throw "파일 없음: $p" }

# Patch136을 이미 적용했다면 잘못된 legacy 추정 로직은 Patch136 직전 백업으로 제거.
$bak = "$p.bak_before_patch136"
if (Test-Path $bak) {
  Copy-Item $p "$p.before_patch136b" -Force
  Copy-Item $bak $p -Force
  Write-Host "[OK] Patch136의 잘못된 열 추정 로직 제거 후 정상본 복원" -ForegroundColor Green
} else {
  Copy-Item $p "$p.bak_before_patch136b" -Force
}

$s = Get-Content $p -Raw -Encoding UTF8

$old = @'
    final cellPattern = RegExp(
      r'<c\b([^>]*)>([\s\S]*?)</c>|<c\b([^>]*)/>',
      caseSensitive: false,
    );

    for (final rowMatch in rowPattern.allMatches(xml)) {
      final rowXml = rowMatch.group(1) ?? '';
      final values = <String>[];

      for (final cellMatch in cellPattern.allMatches(rowXml)) {
        final attrs = cellMatch.group(1) ?? cellMatch.group(3) ?? '';
        final body = cellMatch.group(2) ?? '';
'@

$new = @'
    // 중요: self-closing 빈 셀(<c .../>)이 다음 일반 셀(<c ...>...</c>)을
    // 삼키지 않도록 하나의 패턴으로 처리합니다.
    // 예: <c r="D6" .../><c r="E6" ...><v>...</v></c>
    // 기존 정규식은 D6부터 E6의 </c>까지 한 셀로 오인할 수 있었습니다.
    final cellPattern = RegExp(
      r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)',
      caseSensitive: false,
    );

    for (final rowMatch in rowPattern.allMatches(xml)) {
      final rowXml = rowMatch.group(1) ?? '';
      final values = <String>[];

      for (final cellMatch in cellPattern.allMatches(rowXml)) {
        final attrs = cellMatch.group(1) ?? '';
        final body = cellMatch.group(2) ?? '';
'@

if (!$s.Contains($old)) {
  throw "excel_import_service.dart의 cellPattern 원본 블록을 찾지 못했습니다."
}
$s = $s.Replace($old,$new)
Set-Content $p $s -Encoding UTF8

Write-Host "[OK] Excel import self-closing cell parser 수정" -ForegroundColor Green
Write-Host "[OK] E열 수신인/F열 전화번호 등 실제 셀 위치 그대로 읽음" -ForegroundColor Green
Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
Write-Host "flutter run"
Write-Host ""
Write-Host "그 후 동일 V08 파일을 다시 업로드하세요." -ForegroundColor Yellow
