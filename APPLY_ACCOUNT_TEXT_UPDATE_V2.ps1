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

  # BCEL 제목 폰트 19 -> 22.
  # 공백/줄바꿈 차이를 허용하되 _payment 함수 내부의 정확한 구문만 1회 변경.
  $paymentPattern = '(?s)(_text\s*\(\s*c,\s*title,\s*Rect\.fromLTWH\(r\.left\s*\+\s*144,\s*r\.top\s*\+\s*8,\s*r\.width\s*-\s*150,\s*)30(\s*\),\s*)19(\s*,\s*bold:\s*true,\s*center:\s*true\s*\);)'
  $paymentMatches = [regex]::Matches($src, $paymentPattern)
  if ($paymentMatches.Count -ne 1) {
    throw "$rel : BCEL 제목 코드 탐색 결과가 $($paymentMatches.Count)개입니다. 안전을 위해 중단합니다."
  }
  $src = [regex]::Replace($src, $paymentPattern, '${1}32${2}22${3}', 1)

  # 상세 계좌 영역 시작 위치를 제목 확대에 맞춰 40 -> 42, 높이 98 -> 96.
  $detailPattern = '(?s)(_text\s*\(\s*c,\s*detail,\s*Rect\.fromLTWH\(r\.left\s*\+\s*144,\s*r\.top\s*\+\s*)40(\s*,\s*r\.width\s*-\s*150,\s*)98(\s*\),\s*16\s*,\s*bold:\s*true\s*\);)'
  $detailMatches = [regex]::Matches($src, $detailPattern)
  if ($detailMatches.Count -ne 1) {
    throw "$rel : BCEL 상세 코드 탐색 결과가 $($detailMatches.Count)개입니다. 안전을 위해 중단합니다."
  }
  $src = [regex]::Replace($src, $detailPattern, '${1}42${2}96${3}', 1)

  # 한국 원화 계좌 블록은 문자열 내용과 글자 크기만 변경.
  # 현재 master의 '한국 원화 계좌:' ~ '박성호' 블록을 공백/개행 형태와 무관하게 찾음.
  $krwPattern = "(?s)'한국 원화 계좌:\\\\\s*경남은행\\\\\s*571-22-0330221\\\\\s*박성호'(\s*,\s*payRects\[3\]\.deflate\(8\)\s*,\s*)18(\s*,\s*bold:\s*true\s*,\s*center:\s*true\s*,?\s*\))"
  $krwMatches = [regex]::Matches($src, $krwPattern)
  if ($krwMatches.Count -ne 1) {
    throw "$rel : 한국 원화 계좌 코드 탐색 결과가 $($krwMatches.Count)개입니다. 안전을 위해 중단합니다."
  }

  $newKrw = "'한국 원화 계좌:\`n경남은행\`n571-22-0330221\`n(4) 박성호\`n(5) 박성호(엘케이무역)'"
  $src = [regex]::Replace(
    $src,
    $krwPattern,
    { param($m) $newKrw + $m.Groups[1].Value + '22' + $m.Groups[2].Value },
    1
  )

  if ($src -eq $original) { throw "$rel : 변경 사항이 없습니다." }

  $backup = "$path.bak_before_account_text_update_v2"
  if (!(Test-Path $backup)) { Copy-Item $path $backup -Force }
  Set-Content -Path $path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $rel"
}

Write-Host ""
Write-Host "완료: 가견적서/거래명세서 계좌 표시 수정 완료"
Write-Host "SQL 변경 없음."
