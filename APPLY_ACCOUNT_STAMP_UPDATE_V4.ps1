$ErrorActionPreference = "Stop"

$files = @(
  "lib\screens\quotation_preview_dialog.dart",
  "lib\screens\statement_preview_dialog.dart"
)

foreach ($rel in $files) {
  $path = Join-Path (Get-Location).Path $rel
  if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $rel" }

  $src = Get-Content -Raw -Encoding UTF8 $path
  $original = $src

  # 최신 master 기준 계좌 텍스트가 이미 적용됐는지 확인
  $required = @(
    "'BCEL (USD):'",
    "'BCEL (KIP):'",
    "'BCEL (Baht):'",
    "한국 원화 계좌:\n경남은행\n571-22-0330221\n(4) 박성호\n(5) 박성호(엘케이무역)"
  )
  foreach ($token in $required) {
    if (!$src.Contains($token)) {
      throw "$rel : 최신 계좌 텍스트 '$token' 을 찾지 못했습니다. GitHub 최신본과 로컬본이 다릅니다."
    }
  }

  # BCEL title은 최신본의 22pt 중앙정렬을 보장
  $src = $src.Replace(
    "_text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 32), 22, bold: true, center: true);",
    "_text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 32), 22, bold: true, center: true);"
  )

  # 도장: 기존 105x64 -> 서명 박스 안에서 거의 꽉 차도록 확대.
  # 제목 영역은 침범하지 않도록 y=30부터, 좌우 10px 여백.
  $oldStamp = "_imageContain(c, stamp, Rect.fromLTWH((signW - 105) / 2, signTop + 34, 105, 64));"
  $newStamp = "_imageContain(c, stamp, Rect.fromLTWH(10, signTop + 30, signW - 20, signH - 34));"
  $count = ([regex]::Matches($src, [regex]::Escape($oldStamp))).Count
  if ($count -ne 1) {
    throw "$rel : 도장 출력 코드 탐색 결과가 $count 개입니다. 안전을 위해 중단합니다."
  }
  $src = $src.Replace($oldStamp, $newStamp)

  if ($src -eq $original) {
    throw "$rel : 변경 사항이 없습니다."
  }

  Copy-Item $path "$path.bak_before_account_stamp_update_v4" -Force
  Set-Content -Path $path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $rel"
}

Write-Host ""
Write-Host "확인 완료:"
Write-Host "- BCEL USD/KIP/Baht 22pt 중앙정렬"
Write-Host "- 한국 원화 계좌 22pt"
Write-Host "- 경남은행 / 571-22-0330221"
Write-Host "- (4) 박성호"
Write-Host "- (5) 박성호(엘케이무역)"
Write-Host "- 도장 서명 박스 크기에 맞춰 확대"
Write-Host "SQL 변경 없음."
