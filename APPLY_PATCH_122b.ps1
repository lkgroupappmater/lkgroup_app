$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Path = Join-Path $Root "lib\screens\change_approval_screen.dart"

if (!(Test-Path $Path)) {
  throw "대상 파일을 찾을 수 없습니다: $Path"
}

Copy-Item $Path "$Path.bak_before_patch122b" -Force
$text = Get-Content $Path -Raw -Encoding UTF8

if ($text -match "_autoUnmatched = autoUnmatched;" -and $text -notmatch "final autoUnmatched\s*=") {
  $needle = "      final unknownClaims =`r`n          await UnknownRecipientService.instance.listPendingClaimsForAdmin();"
  $replacement = "      final unknownClaims =`r`n          await UnknownRecipientService.instance.listPendingClaimsForAdmin();`r`n      final autoUnmatched =`r`n          await UnknownRecipientService.instance.listAutoUnmatchedForAdmin();"

  if ($text.Contains($needle)) {
    $text = $text.Replace($needle, $replacement)
  } else {
    $needleLf = "      final unknownClaims =`n          await UnknownRecipientService.instance.listPendingClaimsForAdmin();"
    $replacementLf = "      final unknownClaims =`n          await UnknownRecipientService.instance.listPendingClaimsForAdmin();`n      final autoUnmatched =`n          await UnknownRecipientService.instance.listAutoUnmatchedForAdmin();"
    if ($text.Contains($needleLf)) {
      $text = $text.Replace($needleLf, $replacementLf)
    } else {
      throw "autoUnmatched 변수 삽입 위치를 찾지 못했습니다."
    }
  }

  Set-Content $Path $text -Encoding UTF8
  Write-Host "Patch122b 적용 완료: autoUnmatched 조회 변수 추가"
} else {
  Write-Host "Patch122b: 이미 수정되어 있거나 대상 패턴이 없습니다."
}

Write-Host "이제 flutter analyze 를 실행해 주세요."
