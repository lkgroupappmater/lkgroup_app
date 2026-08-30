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

  # 1) BCEL 상세 계좌 텍스트: 제목과 같은 22pt + 구획 중앙정렬
  $oldPayment = @"
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 42, r.width - 150, 96),
        16, bold: true);
"@
  $newPayment = @"
    _text(c, detail, Rect.fromLTWH(r.left + 144, r.top + 42, r.width - 150, 96),
        22, bold: true, center: true);
"@
  if (!$src.Contains($oldPayment)) {
    throw "$rel : BCEL 상세 텍스트 코드를 찾지 못했습니다. 최신 master와 로컬 파일이 다른지 확인하세요."
  }
  $src = $src.Replace($oldPayment, $newPayment)

  # 2) 한국 원화 계좌 기본 표시는 4번 계좌만
  $oldAccount = "한국 원화 계좌:\n경남은행\n571-22-0330221\n(4) 박성호\n(5) 박성호(엘케이무역)"
  $newAccount = "한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호"
  if (!$src.Contains($oldAccount)) {
    throw "$rel : 기존 한국 원화 계좌 문자열을 찾지 못했습니다."
  }
  $src = $src.Replace($oldAccount, $newAccount)

  # 해당 한국계좌 호출은 4줄이므로 maxLines 5 -> 4
  $accountPos = $src.IndexOf($newAccount)
  if ($accountPos -lt 0) { throw "$rel : 변경한 한국 원화 계좌 문자열을 찾지 못했습니다." }
  $callStart = $src.LastIndexOf("_text(", $accountPos)
  $callEnd = $src.IndexOf(");", $accountPos)
  if ($callStart -lt 0 -or $callEnd -lt 0) { throw "$rel : 한국계좌 _text 호출 범위를 찾지 못했습니다." }
  $callEnd += 2
  $accountCall = $src.Substring($callStart, $callEnd - $callStart)
  $accountCall = $accountCall.Replace("maxLines: 5", "maxLines: 4")
  $src = $src.Substring(0, $callStart) + $accountCall + $src.Substring($callEnd)

  # 3) 도장: 원본 PNG의 투명 여백 때문에 보이는 도장이 작아지는 문제 보정.
  #    도장에만 중앙 64% 영역을 source crop하여 서명칸 안에서 최대 확대.
  $oldStamp = "_imageContain(c, stamp, Rect.fromLTWH(10, signTop + 30, signW - 20, signH - 34));"
  $newStamp = "_imageContainTrimmed(c, stamp, Rect.fromLTWH(8, signTop + 27, signW - 16, signH - 29), trimRatio: .18);"
  if (!$src.Contains($oldStamp)) {
    throw "$rel : 도장 출력 코드를 찾지 못했습니다."
  }
  $src = $src.Replace($oldStamp, $newStamp)

  if (!$src.Contains("void _imageContainTrimmed(")) {
    $marker = "  void _imageContain(Canvas c, ui.Image image, Rect box) {"
    $idx = $src.IndexOf($marker)
    if ($idx -lt 0) { throw "$rel : _imageContain 함수를 찾지 못했습니다." }

    $helper = @"
  void _imageContainTrimmed(
    Canvas c,
    ui.Image image,
    Rect box, {
    double trimRatio = .18,
  }) {
    final insetX = image.width * trimRatio;
    final insetY = image.height * trimRatio;
    final source = Rect.fromLTRB(
      insetX,
      insetY,
      image.width - insetX,
      image.height - insetY,
    );
    final ratio = source.width / source.height;
    var dw = box.width;
    var dh = dw / ratio;
    if (dh > box.height) {
      dh = box.height;
      dw = dh * ratio;
    }
    final dst = Rect.fromLTWH(
      box.left + (box.width - dw) / 2,
      box.top + (box.height - dh) / 2,
      dw,
      dh,
    );
    c.drawImageRect(image, source, dst, Paint());
  }

"@
    $src = $src.Insert($idx, $helper)
  }

  if ($src -eq $original) { throw "$rel : 변경 사항이 없습니다." }

  Copy-Item $path "$path.bak_before_patch114" -Force
  Set-Content -Path $path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $rel"
}

Write-Host ""
Write-Host "Patch114 화면 출력 수정 완료"
Write-Host "- BCEL 상세 계좌 텍스트 22pt / 중앙정렬"
Write-Host "- 일반 한국계좌는 경남은행 571-22-0330221 박성호만 표시"
Write-Host "- 도장 투명여백 보정 + 서명칸 최대 확대"
Write-Host "- 다른 화면/구조/기능 변경 없음"
