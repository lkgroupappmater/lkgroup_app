$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function Read-Utf8($path) { Get-Content $path -Raw -Encoding UTF8 }
function Write-Utf8($path,$text) { Set-Content $path $text -Encoding UTF8 }

# -------------------------------------------------------------------
# 1) 사용자가 업로드한 실제 Excel의 Camera/연결그림 명세서 원본으로 교체
#    - 임의 crop asset이 아니라 각 XLSX에 실제 포함된 명세서 form
#    - 상단 빈 캔버스 제거된 clean form
# -------------------------------------------------------------------
$assetDst = Join-Path $project 'assets\statement_forms'
if (-not (Test-Path $assetDst)) {
  throw "statement_forms asset folder not found: $assetDst"
}

# -------------------------------------------------------------------
# 2) 명세서 Painter: clean Excel form 좌표계로 복귀
# -------------------------------------------------------------------
$sPath = Join-Path $project 'lib/screens/statement_preview_dialog.dart'
$s = Read-Utf8 $sPath

# 더 이상 상단 빈 공간을 runtime에서 잘라내지 않는다.
$s = [regex]::Replace(
  $s,
  "double _cropRatio\(\) =>[\s\S]*?;\r?\n\s*Size _logicalSize",
  "double _cropRatio() => 0.0;`r`n  Size _logicalSize",
  1
)

# clean asset 자체가 문서 경계이므로 좌우 추가 crop도 하지 않는다.
$s = [regex]::Replace(
  $s,
  "Rect _documentRect\(ui\.Image image\) \{[\s\S]*?\r?\n  \}",
@"
Rect _documentRect(ui.Image image) {
    final logical = _logicalSize(image);
    return Rect.fromLTWH(0, 0, logical.width, logical.height);
  }
"@,
  1
)

# clean form의 실제 Excel 행 좌표: 첫 상세행 약 18.3%, 행 높이 약 2.2%
$s = $s.Replace("    final rowH = h * .028;", "    final rowH = h * .0220;")
$s = $s.Replace("    final bodyTop = h * .245;", "    final bodyTop = h * .1830;")

# 넓은 흰색 마스크 + 수동 가로선 재작성은 Excel 서식을 훼손하므로 제거.
$maskStart = $s.IndexOf("    // 기존 샘플 값만 흰색으로 지우고 실제 DB 값을 오버레이.")
$receiptStart = $s.IndexOf("    _text(canvas, receiptNumber", $maskStart)
if ($maskStart -ge 0 -and $receiptStart -gt $maskStart) {
  $replacement = @'
    // Excel 원본의 선/색/폰트/셀 서식을 그대로 유지한다.
    // 값이 들어가는 셀의 '안쪽'만 지워서 border는 절대 덮지 않는다.
    final xx = <double>[
      w * .0020, w * .0600, w * .1510, w * .1790, w * .2210,
      w * .3030, w * .4120, w * .4400, w * .4700, w * .5010,
      w * .5990, w * .7120, w * .8180, w * .9010, w * .9980,
    ];
    final white = Paint()..color = Colors.white;

    void clearCell(int c, double top, double bottom) {
      if (c < 0 || c >= xx.length - 1) return;
      canvas.drawRect(
        Rect.fromLTRB(
          xx[c] + 2.0,
          top + 2.0,
          xx[c + 1] - 2.0,
          bottom - 2.0,
        ),
        white,
      );
    }

    // 고객명/연락처/영수번호 영역도 셀 border를 남기고 내부만 갱신.
    canvas.drawRect(
      Rect.fromLTRB(w * .575, h * .062, w * .997, h * .118),
      white,
    );

'@
  $s = $s.Substring(0,$maskStart) + $replacement + $s.Substring($receiptStart)
}

# 고객/영수번호/도착일 위치를 clean Excel form 기준으로 조정
$s = $s.Replace("Offset(w * .865, h * .105)", "Offset(w * .865, h * .073)")
$s = $s.Replace("Offset(w * .72, h * .105)", "Offset(w * .72, h * .073)")
$s = $s.Replace("Offset(w * .35, h * .105)", "Offset(w * .35, h * .073)")

# 상세행: 각 셀 안쪽만 clear 후 값 표시
$loopNeedle = "      final line = i < lines.length ? lines[i] : null;"
$loopInsert = @'
      final line = i < lines.length ? lines[i] : null;
      final cellTop = bodyTop + i * rowH;
      final cellBottom = cellTop + rowH;
      for (var c = 0; c < xx.length - 1; c++) {
        clearCell(c, cellTop, cellBottom);
      }
'@
$s = $s.Replace($loopNeedle,$loopInsert)

# 기존 데이터 텍스트 위치도 새 Excel 행 좌표에 맞춤
$s = $s.Replace("final y = bodyTop + i * rowH + rowH * .18;", "final y = bodyTop + i * rowH + rowH * .16;")

# 최종 청구 금액 block은 실제 Excel form 위치 기준
$s = $s.Replace("final totalY = h * .53 + shift;", "final totalY = h * .465 + shift;")
$s = $s.Replace("totalY + h * .027", "totalY + h * .026")
$s = $s.Replace("totalY + h * .052", "totalY + h * .052")
$s = $s.Replace("totalY + h * .077", "totalY + h * .078")

# clean form은 제목이 맨 위이므로 과거 blank-canvas용 .472 좌표 제거
$s = $s.Replace(
"final rect = Rect.fromLTRB(w * .19, h * .472, w * .81, h * .525);",
"final rect = Rect.fromLTRB(w * .19, h * .008, w * .81, h * .073);"
)
$s = $s.Replace(
"// statement PNG는 상단에 원본 링크 이미지 여백이 있으므로 실제 문서 타이틀 위치에 덮어씀.",
"// 실제 Excel 명세서 form의 제목 셀만 현재 route document_title로 갱신."
)

Write-Utf8 $sPath $s

# -------------------------------------------------------------------
# 3) 견적서: 원본 Excel form은 유지, overlay 글자만 Excel 가독성에 맞춤
#    현재 문제의 핵심은 2292px 원본에 13px 고정 글자를 사용한 것.
# -------------------------------------------------------------------
$qPath = Join-Path $project 'lib/screens/quotation_preview_dialog.dart'
$q = Read-Utf8 $qPath

# 상세 데이터: 13~15px 고정 -> 원본 폭 기준 18~20px
$q = $q.Replace("c >= 11 ? 14 : 13,", "c >= 11 ? 20 : 18,")
$q = $q.Replace("        15,`r`n        bold: true,", "        20,`r`n        bold: true,")
$q = $q.Replace("        15,`n        bold: true,", "        20,`n        bold: true,")
$q = $q.Replace("Rect.fromLTRB(xx[3], top, xx[4], bottom), 15, bold: true",
                "Rect.fromLTRB(xx[3], top, xx[4], bottom), 19, bold: true")
$q = $q.Replace("Rect.fromLTRB(xx[5], top, xx[6], bottom), 15, bold: true",
                "Rect.fromLTRB(xx[5], top, xx[6], bottom), 19, bold: true")
$q = $q.Replace("Rect.fromLTRB(xx[10], top, xx[11], bottom), 15, bold: true",
                "Rect.fromLTRB(xx[10], top, xx[11], bottom), 19, bold: true")
$q = $q.Replace("      16,`r`n      bold: true,", "      20,`r`n      bold: true,")
$q = $q.Replace("      16,`n      bold: true,", "      20,`n      bold: true,")

# Excel 원본 글자와 과도하게 다른 두꺼운 overlay를 완화
$q = $q.Replace(
"fontWeight: bold ? FontWeight.w700 : FontWeight.w500,",
"fontWeight: bold ? FontWeight.w600 : FontWeight.w400,"
)

Write-Utf8 $qPath $q

Write-Host ''
Write-Host 'Patch099 적용 완료' -ForegroundColor Green
Write-Host '- 명세서: 업로드 Excel에 실제 포함된 Camera/연결그림 form으로 전면 교체'
Write-Host '- 명세서: 과거 상단 blank crop/sourceTop 좌표 제거'
Write-Host '- 명세서: 넓은 흰색 overlay 제거, 셀 내부만 갱신하여 Excel border/서식 보존'
Write-Host '- 견적서: 기존 Excel form 유지 + 데이터 폰트 가독성/굵기 정상화'
Write-Host '- Preview와 저장은 동일 Painter 사용'
Write-Host ''
Write-Host 'flutter analyze 실행 후 flutter run 하세요.'

