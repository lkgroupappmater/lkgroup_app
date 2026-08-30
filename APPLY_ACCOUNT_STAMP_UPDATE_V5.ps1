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

  # ------------------------------------------------------------
  # 1) BCEL 제목: 22pt + 중앙정렬 보장
  # ------------------------------------------------------------
  $paymentStart = $src.IndexOf("void _payment(")
  if ($paymentStart -lt 0) { throw "$rel : _payment 함수를 찾을 수 없습니다." }

  $paymentEnd = $src.IndexOf("void ", $paymentStart + 10)
  if ($paymentEnd -lt 0) { $paymentEnd = $src.Length }

  $seg = $src.Substring($paymentStart, $paymentEnd - $paymentStart)

  $titlePattern = '(?s)_text\s*\(\s*c\s*,\s*title\s*,\s*Rect\.fromLTWH\((.*?)\)\s*,\s*\d+(?:\.\d+)?\s*,\s*bold\s*:\s*true\s*,\s*center\s*:\s*true\s*\)\s*;'
  $tm = [regex]::Matches($seg, $titlePattern)
  if ($tm.Count -ne 1) { throw "$rel : BCEL 제목 출력 코드 탐색 결과가 $($tm.Count)개입니다." }

  $oldTitle = $tm[0].Value
  $newTitle = [regex]::Replace(
      $oldTitle,
      '\)\s*,\s*\d+(?:\.\d+)?\s*,\s*bold\s*:\s*true\s*,\s*center\s*:\s*true',
      '), 22, bold: true, center: true',
      1
  )
  $seg = $seg.Replace($oldTitle, $newTitle)

  # detail은 기존 폰트 유지. 제목 아래 공간만 확보
  $seg = [regex]::Replace(
      $seg,
      '(Rect\.fromLTWH\(r\.left\s*\+\s*144\s*,\s*r\.top\s*\+\s*)\d+(\s*,\s*r\.width\s*-\s*150\s*,\s*)\d+(\s*\)\s*,\s*16\s*,\s*bold\s*:\s*true)',
      '${1}42${2}96${3}',
      1
  )

  $src = $src.Substring(0, $paymentStart) + $seg + $src.Substring($paymentEnd)

  # ------------------------------------------------------------
  # 2) 원화 계좌 텍스트를 요청 내용으로 확정
  # ------------------------------------------------------------
  $krwStart = $src.IndexOf("한국 원화 계좌:")
  if ($krwStart -lt 0) { throw "$rel : 한국 원화 계좌 문자열을 찾을 수 없습니다." }

  # 해당 문자열을 포함하는 _text(...) 호출 전체를 찾음
  $callStart = $src.LastIndexOf("_text(", $krwStart)
  if ($callStart -lt 0) { throw "$rel : 원화 계좌 _text 시작을 찾을 수 없습니다." }

  $callEnd = $src.IndexOf(");", $krwStart)
  if ($callEnd -lt 0) { throw "$rel : 원화 계좌 _text 끝을 찾을 수 없습니다." }
  $callEnd += 2

  $krwCall = $src.Substring($callStart, $callEnd - $callStart)

  $quoteStartSingle = $krwCall.IndexOf("'한국 원화 계좌:")
  $quoteStartDouble = $krwCall.IndexOf('"한국 원화 계좌:')
  if ($quoteStartSingle -ge 0) {
    $q = "'"
    $qs = $quoteStartSingle
  } elseif ($quoteStartDouble -ge 0) {
    $q = '"'
    $qs = $quoteStartDouble
  } else {
    throw "$rel : 원화 계좌 문자열 시작 따옴표를 찾을 수 없습니다."
  }

  $qe = $krwCall.IndexOf($q, $qs + 1)
  while ($qe -gt 0 -and $krwCall[$qe - 1] -eq '\') {
    $qe = $krwCall.IndexOf($q, $qe + 1)
  }
  if ($qe -lt 0) { throw "$rel : 원화 계좌 문자열 끝 따옴표를 찾을 수 없습니다." }

  $newText = $q + "한국 원화 계좌:\n경남은행\n571-22-0330221\n(4) 박성호\n(5) 박성호(엘케이무역)" + $q
  $krwCall = $krwCall.Substring(0, $qs) + $newText + $krwCall.Substring($qe + 1)

  # font size -> 22
  $krwCall = [regex]::Replace(
      $krwCall,
      '(payRects\[3\]\.deflate\(8\)\s*,\s*)\d+(?:\.\d+)?(\s*,)',
      '${1}22${2}',
      1
  )

  # maxLines: 5를 이 호출에만 추가
  if ($krwCall -notmatch 'maxLines\s*:') {
    $krwCall = [regex]::Replace(
        $krwCall,
        '(center\s*:\s*true\s*,?)',
        '$1' + "`r`n      maxLines: 5,",
        1
    )
  }

  $src = $src.Substring(0, $callStart) + $krwCall + $src.Substring($callEnd)

  # ------------------------------------------------------------
  # 3) _text 함수에 maxLines 옵션 추가 (기본 3, 다른 출력 영향 없음)
  # ------------------------------------------------------------
  if ($src -notmatch 'int\s+maxLines\s*=\s*3') {
    $sigPattern = '(void\s+_text\s*\(\s*Canvas\s+c\s*,\s*String\s+text\s*,\s*Rect\s+r\s*,\s*double\s+size\s*,\s*\{\s*bool\s+bold\s*=\s*false\s*,\s*bool\s+center\s*=\s*false\s*,\s*bool\s+right\s*=\s*false)(\s*\}\s*\))'
    $sm = [regex]::Matches($src, $sigPattern)
    if ($sm.Count -ne 1) { throw "$rel : _text 함수 선언 탐색 결과가 $($sm.Count)개입니다." }
    $src = [regex]::Replace($src, $sigPattern, '${1}, int maxLines = 3${2}', 1)
  }

  $maxLinePattern = 'maxLines\s*:\s*3\s*,'
  $matches = [regex]::Matches($src, $maxLinePattern)
  if ($matches.Count -lt 1) { throw "$rel : TextPainter maxLines: 3 을 찾을 수 없습니다." }

  # _text 함수 내부의 maxLines만 변수로 변경
  $textFuncStart = $src.IndexOf("void _text(")
  $textFuncEnd = $src.IndexOf("@override", $textFuncStart)
  if ($textFuncEnd -lt 0) { $textFuncEnd = $src.Length }
  $textFunc = $src.Substring($textFuncStart, $textFuncEnd - $textFuncStart)
  $textFunc2 = [regex]::Replace($textFunc, 'maxLines\s*:\s*3\s*,', 'maxLines: maxLines,', 1)
  if ($textFunc2 -eq $textFunc) { throw "$rel : _text 내부 maxLines 변경 실패." }
  $src = $src.Substring(0, $textFuncStart) + $textFunc2 + $src.Substring($textFuncEnd)

  # ------------------------------------------------------------
  # 4) 도장: 현재 크기와 무관하게 stamp용 Rect 호출을 찾아 확대
  # ------------------------------------------------------------
  $stampPattern = '_imageContain\s*\(\s*c\s*,\s*stamp\s*,\s*Rect\.fromLTWH\([^;]*?\)\s*\)\s*;'
  $stampMatches = [regex]::Matches($src, $stampPattern)
  if ($stampMatches.Count -ne 1) {
    throw "$rel : 도장 출력 코드 탐색 결과가 $($stampMatches.Count)개입니다."
  }

  $newStamp = "_imageContain(c, stamp, Rect.fromLTWH(10, signTop + 30, signW - 20, signH - 34));"
  $src = [regex]::Replace($src, $stampPattern, $newStamp, 1)

  # ------------------------------------------------------------
  # 5) 최종 검증
  # ------------------------------------------------------------
  $checks = @(
    "BCEL (USD):",
    "BCEL (KIP):",
    "BCEL (Baht):",
    "한국 원화 계좌:\n경남은행\n571-22-0330221\n(4) 박성호\n(5) 박성호(엘케이무역)",
    "maxLines: 5",
    "signW - 20"
  )
  foreach ($check in $checks) {
    if (!$src.Contains($check)) { throw "$rel : 최종 검증 실패 -> $check" }
  }

  if ($src -eq $original) {
    Write-Host "이미 동일 적용 상태: $rel"
    continue
  }

  Copy-Item $path "$path.bak_before_account_stamp_update_v5" -Force
  Set-Content -Path $path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $rel"
}

Write-Host ""
Write-Host "V5 적용 완료"
Write-Host "- BCEL 제목 22pt / 중앙정렬"
Write-Host "- 한국 원화 계좌 22pt / 5줄 표시"
Write-Host "- 경남은행 / 계좌번호 / (4) / (5)"
Write-Host "- 도장 박스에 맞춰 확대"
Write-Host "- 다른 _text 출력은 maxLines 기본값 3 유지"
Write-Host "- SQL 변경 없음."
