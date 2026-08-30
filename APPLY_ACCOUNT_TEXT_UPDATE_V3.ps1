$ErrorActionPreference = "Stop"

function Replace-OnceInRange {
  param(
    [string]$Text,
    [int]$Start,
    [int]$End,
    [string]$Old,
    [string]$New,
    [string]$Label
  )
  if ($Start -lt 0 -or $End -le $Start) { throw "$Label : 잘못된 탐색 범위입니다." }
  $segment = $Text.Substring($Start, $End - $Start)
  $count = ([regex]::Matches($segment, [regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "$Label : '$Old' 탐색 결과가 $count 개입니다. 안전을 위해 중단합니다." }
  $segment = $segment.Replace($Old, $New)
  return $Text.Substring(0, $Start) + $segment + $Text.Substring($End)
}

$files = @(
  "lib\screens\quotation_preview_dialog.dart",
  "lib\screens\statement_preview_dialog.dart"
)

foreach ($rel in $files) {
  $path = Join-Path (Get-Location).Path $rel
  if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $rel" }

  $src = Get-Content -Raw -Encoding UTF8 $path
  $original = $src

  # ------------------------------------------------------------
  # 1) _payment 함수 내부만 수정
  # ------------------------------------------------------------
  $paymentStart = $src.IndexOf("void _payment(")
  if ($paymentStart -lt 0) { throw "$rel : _payment 함수를 찾을 수 없습니다." }

  $paymentEnd = $src.IndexOf("void ", $paymentStart + 10)
  if ($paymentEnd -lt 0) { $paymentEnd = $src.Length }

  # title 영역: 19 -> 22, 높이 30 -> 32
  $paymentSegment = $src.Substring($paymentStart, $paymentEnd - $paymentStart)

  $titleAnchor = $paymentSegment.IndexOf("_text(c, title")
  if ($titleAnchor -lt 0) { throw "$rel : BCEL title 출력 코드를 찾을 수 없습니다." }

  $titleEnd = $paymentSegment.IndexOf(");", $titleAnchor)
  if ($titleEnd -lt 0) { throw "$rel : BCEL title 출력 코드 끝을 찾을 수 없습니다." }
  $titleEnd += 2

  $absoluteTitleStart = $paymentStart + $titleAnchor
  $absoluteTitleEnd = $paymentStart + $titleEnd

  $titleBlock = $src.Substring($absoluteTitleStart, $absoluteTitleEnd - $absoluteTitleStart)
  if ($titleBlock -notmatch "center\s*:\s*true") {
    throw "$rel : BCEL title 중앙정렬 코드가 예상과 다릅니다."
  }

  # 숫자는 title block 안에서만 변경
  $titleBlock2 = $titleBlock
  $titleBlock2 = [regex]::Replace($titleBlock2, ',\s*30\s*\)', ', 32)', 1)
  $titleBlock2 = [regex]::Replace($titleBlock2, '\)\s*,\s*19\s*,', '), 22,', 1)

  if ($titleBlock2 -eq $titleBlock) {
    throw "$rel : BCEL title 글자크기 변경점을 찾지 못했습니다."
  }
  $src = $src.Substring(0, $absoluteTitleStart) + $titleBlock2 + $src.Substring($absoluteTitleEnd)

  # detail 영역은 함수 범위를 다시 계산
  $paymentStart = $src.IndexOf("void _payment(")
  $paymentEnd = $src.IndexOf("void ", $paymentStart + 10)
  if ($paymentEnd -lt 0) { $paymentEnd = $src.Length }
  $paymentSegment = $src.Substring($paymentStart, $paymentEnd - $paymentStart)

  $detailAnchor = $paymentSegment.IndexOf("_text(c, detail")
  if ($detailAnchor -ge 0) {
    $detailEnd = $paymentSegment.IndexOf(");", $detailAnchor)
    if ($detailEnd -gt $detailAnchor) {
      $detailEnd += 2
      $absD1 = $paymentStart + $detailAnchor
      $absD2 = $paymentStart + $detailEnd
      $detailBlock = $src.Substring($absD1, $absD2 - $absD1)
      $detailBlock2 = [regex]::Replace($detailBlock, 'r\.top\s*\+\s*40', 'r.top + 42', 1)
      $detailBlock2 = [regex]::Replace($detailBlock2, ',\s*98\s*\)', ', 96)', 1)
      $src = $src.Substring(0, $absD1) + $detailBlock2 + $src.Substring($absD2)
    }
  }

  # ------------------------------------------------------------
  # 2) 한국 원화 계좌 블록
  # 정확한 줄바꿈 문법을 가정하지 않고, 문자열 시작과 payRects[3]만 기준으로 교체
  # ------------------------------------------------------------
  $krwStart = $src.IndexOf("'한국 원화 계좌:")
  if ($krwStart -lt 0) {
    # 큰따옴표 버전 대비
    $krwStart = $src.IndexOf('"한국 원화 계좌:')
  }
  if ($krwStart -lt 0) { throw "$rel : '한국 원화 계좌' 문자열 시작을 찾을 수 없습니다." }

  $payAnchor = $src.IndexOf("payRects[3].deflate(8)", $krwStart)
  if ($payAnchor -lt 0 -or ($payAnchor - $krwStart) -gt 800) {
    throw "$rel : 한국 원화 계좌 payRects[3] 연결부를 찾을 수 없습니다."
  }

  # 문자열의 닫는 따옴표는 payAnchor 직전의 마지막 따옴표 사용
  $beforePay = $src.Substring($krwStart, $payAnchor - $krwStart)
  $singleQuoteEnd = $beforePay.LastIndexOf("'")
  $doubleQuoteEnd = $beforePay.LastIndexOf('"')

  if ($singleQuoteEnd -gt 0) {
    $quote = "'"
    $stringEndRel = $singleQuoteEnd
  } elseif ($doubleQuoteEnd -gt 0) {
    $quote = '"'
    $stringEndRel = $doubleQuoteEnd
  } else {
    throw "$rel : 한국 원화 계좌 문자열 끝을 찾을 수 없습니다."
  }

  $stringEnd = $krwStart + $stringEndRel + 1

  # Dart multiline 표기 형식을 건드리지 않기 위해 \n escape를 사용한 단일 문자열로 통일
  if ($quote -eq "'") {
    $newKrwString = "'한국 원화 계좌:\n경남은행\n571-22-0330221\n(4) 박성호\n(5) 박성호(엘케이무역)'"
  } else {
    $newKrwString = '"한국 원화 계좌:\n경남은행\n571-22-0330221\n(4) 박성호\n(5) 박성호(엘케이무역)"'
  }

  $src = $src.Substring(0, $krwStart) + $newKrwString + $src.Substring($stringEnd)

  # 원화 블록의 글자크기: payRects[3] 이후 첫 번째 숫자 size를 22로
  $payAnchor = $src.IndexOf("payRects[3].deflate(8)", $krwStart)
  $krwCallEnd = $src.IndexOf(");", $payAnchor)
  if ($krwCallEnd -lt 0 -or ($krwCallEnd - $payAnchor) -gt 300) {
    throw "$rel : 한국 원화 계좌 _text 호출 끝을 찾을 수 없습니다."
  }

  $krwTail = $src.Substring($payAnchor, $krwCallEnd - $payAnchor + 2)
  # deflate(8), 다음의 font size 숫자만 22로
  $krwTail2 = [regex]::Replace(
    $krwTail,
    '(payRects\[3\]\.deflate\(8\)\s*,\s*)\d+(?:\.\d+)?(\s*,)',
    '${1}22${2}',
    1
  )
  if ($krwTail2 -eq $krwTail) {
    throw "$rel : 한국 원화 계좌 글자 크기 값을 찾지 못했습니다."
  }
  $src = $src.Substring(0, $payAnchor) + $krwTail2 + $src.Substring($krwCallEnd + 2)

  if ($src -eq $original) { throw "$rel : 변경 사항이 없습니다." }

  $backup = "$path.bak_before_account_text_update_v3"
  if (!(Test-Path $backup)) { Copy-Item $path $backup -Force }

  Set-Content -Path $path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $rel"
}

Write-Host ""
Write-Host "완료: 요청된 가견적서/거래명세서 2개 파일만 수정했습니다."
Write-Host "SQL 변경 없음."
