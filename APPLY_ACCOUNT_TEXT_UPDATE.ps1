$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$files = @(
  "lib\screens\quotation_preview_dialog.dart",
  "lib\screens\statement_preview_dialog.dart"
)

foreach ($rel in $files) {
  $path = Join-Path $repo $rel
  if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $rel" }

  $src = Get-Content -Raw -Encoding UTF8 $path
  $original = $src

  # 1) BCEL 제목: 중앙 정렬 유지 + 19 -> 22
  $oldPayment = @'
    _text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 30),
        19, bold: true, center: true);
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 40, r.width - 150, 98),
        16, bold: true);
'@
  $newPayment = @'
    _text(c, title, Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 32),
        22, bold: true, center: true);
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 42, r.width - 150, 96),
        16, bold: true);
'@

  if (!$src.Contains($oldPayment)) {
    throw "$rel : BCEL 출력 블록이 master 예상 코드와 다릅니다. 임의 수정하지 않고 중단합니다."
  }
  $src = $src.Replace($oldPayment, $newPayment)

  # 2) 한국 원화 계좌: BCEL 제목과 같은 22pt, 요청된 (4)/(5) 표기
  $oldKrw = @'
    _text(
      c,
      '한국 원화 계좌:\
경남은행\
571-22-0330221\
박성호',
      payRects[3].deflate(8),
      18,
      bold: true,
      center: true,
    );
'@
  $newKrw = @'
    _text(
      c,
      '한국 원화 계좌:\
경남은행\
571-22-0330221\
(4) 박성호\
(5) 박성호(엘케이무역)',
      payRects[3].deflate(8),
      22,
      bold: true,
      center: true,
    );
'@

  if (!$src.Contains($oldKrw)) {
    throw "$rel : 한국 원화 계좌 출력 블록이 master 예상 코드와 다릅니다. 임의 수정하지 않고 중단합니다."
  }
  $src = $src.Replace($oldKrw, $newKrw)

  if ($src -eq $original) { throw "$rel : 변경 사항이 없습니다." }

  Copy-Item $path "$path.bak_before_account_text_update" -Force
  Set-Content -Path $path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $rel"
}

Write-Host ""
Write-Host "완료: 요청된 2개 파일만 수정했습니다."
Write-Host "SQL 변경 없음."
