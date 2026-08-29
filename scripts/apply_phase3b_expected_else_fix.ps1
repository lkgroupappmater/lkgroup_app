$ErrorActionPreference = 'Stop'
$path = "lib/screens/change_approval_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$text = Get-Content -Raw -Encoding UTF8 $path

# PHASE3B에서:
#   if (_requests.isEmpty && _unknownClaims.isEmpty) ...
#   if (_requests.isNotEmpty) ...[
# 로 바뀌면서 첫 if가 collection-if 형태인데 뒤에 else 없이 다음 if가 붙어
# 기존 괄호 구조와 충돌한 부분을 명시적 독립 collection-if 두 개로 정리한다.
#
# 실제 오류 지점 주변의 불필요한 else 잔재가 있다면 제거.
$text = $text.Replace(
"                    if (_requests.isEmpty && _unknownClaims.isEmpty)`r`n                      const Padding(",
"                    if (_requests.isEmpty && _unknownClaims.isEmpty)`r`n                      const Padding("
)

# 가장 안전한 수정: empty Padding 블록 뒤의 `else ...[` 또는 단독 `else`를
# `_requests.isNotEmpty` collection-if로 치환.
$text = [regex]::Replace(
  $text,
  "(?ms)(if \(_requests\.isEmpty && _unknownClaims\.isEmpty\)\s+const Padding\(.*?\),)\s*else\s*\.\.\.\[",
  '$1' + "`r`n                    if (_requests.isNotEmpty) ...["
)

# 이전 패치가 이미 if로 바꿨지만 `else` 토큰만 남은 형태 보완.
$text = [regex]::Replace(
  $text,
  "(?m)^\s*else\s+(if \(_requests\.isNotEmpty\) \.\.\.\[)",
  "                    `$1"
)

Set-Content -Path $path -Value $text -Encoding UTF8
Write-Host "PHASE 3B expected_else_or_comma repair complete."
Write-Host "Now run: flutter analyze"
