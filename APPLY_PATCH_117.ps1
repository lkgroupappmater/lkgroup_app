$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
  return Get-Content -Raw -Encoding UTF8 $Path
}
function Write-Utf8([string]$Path, [string]$Text) {
  Set-Content -Path $Path -Value $Text -Encoding UTF8
}
function Replace-Required([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  if (!$Text.Contains($Old)) {
    throw "Patch117 중단: '$Label' 기준 코드를 찾지 못했습니다. 현재 파일을 임의 수정하지 않았습니다."
  }
  return $Text.Replace($Old, $New)
}

$project = (Get-Location).Path

# ---------------------------------------------------------------------------
# 1) 화물 관리
# - 맨 상단 '전체' 옆 명세서 보기 => 체크된 영수번호 전체 PDF 팝업
# - 각 항차 우측 명세서 아이콘 => 기존 그룹/영수번호별 명세서 보기로 복구
# - 카드 라벨/구분자/숫자 표시 정리
# ---------------------------------------------------------------------------
$cargo = Join-Path $project "lib\screens\cargo_management_screen.dart"
Copy-Item $cargo "$cargo.bak_before_patch117" -Force
$src = Read-Utf8 $cargo

$oldTop = @'
                    TextButton.icon(
                      onPressed: _results.isEmpty
                          ? null
                          : () {
                              if (_selectedIds.isEmpty) {
                                _message('\uC120\uD0DD\uB41C \uD56D\uCC28\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.');
                                return;
                              }
                              _showStatement();
                            },
                      icon: const Icon(Icons.receipt_long_outlined, size: 17),
                      label: const Text('명세서 보기'),
'@
$newTop = @'
                    TextButton.icon(
                      onPressed: _results.isEmpty ? null : _showBatchStatementPdf,
                      icon: const Icon(Icons.receipt_long_outlined, size: 17),
                      label: const Text('명세서 보기'),
'@
$src = Replace-Required $src $oldTop $newTop "화물관리 상단 명세서 보기"

$src = Replace-Required $src `
  "tooltip: '체크 명세서 PDF 저장',`n                      onPressed: _busy ? null : () => _showBatchStatementPdf(scopeRows: rows)," `
  "tooltip: '명세서 보기',`n                      onPressed: _busy ? null : () => _showGroupStatement(rows)," `
  "항차별 명세서 보기 복구"

$src = $src.Replace("'이름/수령인 & 회사'", "'수령인 / 회사명'")
$src = $src.Replace("'무게/크기(L H W)'", "'무게 / 크기'")
$src = $src.Replace("'영수증 번호 & 구획 (Zone)'", "'영수번호 / 구획'")
$src = $src.Replace("_infoRow('영수증 번호', receipt)", "_infoRow('영수번호', receipt)")
$src = $src.Replace("'`$receipt & `${zone.isEmpty ? '-' : zone}'", "'`$receipt / `${zone.isEmpty ? '-' : zone}'")

# dimensions are displayed as natural numbers; weight always one decimal place.
$src = $src.Replace("final length = '`${item['length_cm'] ?? ''}'.trim();", "final length = _naturalNumber(item['length_cm']);")
$src = $src.Replace("final height = '`${item['height_cm'] ?? ''}'.trim();", "final height = _naturalNumber(item['height_cm']);")
$src = $src.Replace("final width = '`${item['width_cm'] ?? ''}'.trim();", "final width = _naturalNumber(item['width_cm']);")
$src = $src.Replace("'`${item['weight_kg'] ?? ''} kg / `$size'", "'`${_weightOneDecimal(item['weight_kg'])} kg / `$size'")

if (!$src.Contains("String _weightOneDecimal(dynamic value)")) {
$helpers = @'
  String _weightOneDecimal(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.toStringAsFixed(1);
  }

  String _naturalNumber(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.round().toString();
  }

'@
  $src = Replace-Required $src "  String _dateOnly(dynamic value) {" ($helpers + "  String _dateOnly(dynamic value) {") "화물관리 숫자표시 helper"
}
Write-Utf8 $cargo $src
Write-Host "수정 완료: 화물관리 상단 일괄 PDF / 각 항차 명세서 보기 복구 / 카드 라벨 및 숫자 표시"

# ---------------------------------------------------------------------------
# 2) 화물 조회 카드에도 같은 라벨/표시 규칙
# ---------------------------------------------------------------------------
$search = Join-Path $project "lib\screens\shipment_search_screen.dart"
Copy-Item $search "$search.bak_before_patch117" -Force
$src = Read-Utf8 $search

$src = $src.Replace("'이름/수령인 & 회사'", "'수령인 / 회사명'")
$src = $src.Replace("'무게/크기(L H W)'", "'무게 / 크기'")
$src = $src.Replace("'영수증 번호 & 구획 (Zone)'", "'영수번호 / 구획'")
$src = $src.Replace("_row('영수증 번호', receipt)", "_row('영수번호', receipt)")
$src = $src.Replace("'`$receipt & `${zone.isEmpty ? '-' : zone}'", "'`$receipt / `${zone.isEmpty ? '-' : zone}'")

$src = $src.Replace("final length = '`${r['length_cm'] ?? ''}'.trim();", "final length = _naturalNumber(r['length_cm']);")
$src = $src.Replace("final height = '`${r['height_cm'] ?? ''}'.trim();", "final height = _naturalNumber(r['height_cm']);")
$src = $src.Replace("final width = '`${r['width_cm'] ?? ''}'.trim();", "final width = _naturalNumber(r['width_cm']);")
$src = $src.Replace("'`${r['weight_kg'] ?? ''} kg / `$size'", "'`${_weightOneDecimal(r['weight_kg'])} kg / `$size'")

if (!$src.Contains("String _weightOneDecimal(dynamic value)")) {
$helpers = @'
  String _weightOneDecimal(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.toStringAsFixed(1);
  }

  String _naturalNumber(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.round().toString();
  }

'@
  $src = Replace-Required $src "  String _dateOnly(dynamic value) {" ($helpers + "  String _dateOnly(dynamic value) {") "화물조회 숫자표시 helper"
}
Write-Utf8 $search $src
Write-Host "수정 완료: 화물조회 카드 라벨 / 구분자 / 무게 0.0 / 크기 자연수"

# ---------------------------------------------------------------------------
# 3) 가견적서 Remark
# hard-coded 문구를 제거하고 실제 Excel에서 만든 DocumentTextCatalog 사용
# ---------------------------------------------------------------------------
$quote = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
Copy-Item $quote "$quote.bak_before_patch117" -Force
$src = Read-Utf8 $quote

$oldRemark = @'
    _text(
      c,
      '본 가견적은 입력된 중량/규격을 기준으로 한 예상 운임입니다. '
      '실제 입고 후 실측 중량·용적중량 중 큰 값을 운임 적용중량으로 사용하며, '
      '최종 청구금액은 실제 측정 결과에 따라 달라질 수 있습니다.',
      Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
      14,
    );
'@
$newRemark = @'
    _text(
      c,
      docText.remark,
      Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
      docText.remarkFontSize,
      maxLines: 6,
      lineHeight: 1.05,
    );
'@
$src = Replace-Required $src $oldRemark $newRemark "가견적서 Remark 실제 Excel 문구"

$oldFooter = @'
      docText.footerFontSize,
      center: true,
    );
'@
$newFooter = @'
      docText.footerFontSize,
      center: true,
      maxLines: 6,
      lineHeight: 1.05,
    );
'@
$src = Replace-Required $src $oldFooter $newFooter "가견적서 하단 중앙 안내문 크기조절"
Write-Utf8 $quote $src
Write-Host "수정 완료: 가견적서 Remark 실제 운송경로 문구 적용"

# ---------------------------------------------------------------------------
# 4) 명세서도 동일 가독성 규칙만 적용 (문구 자체는 변경 없음)
# ---------------------------------------------------------------------------
$statement = Join-Path $project "lib\screens\statement_preview_dialog.dart"
Copy-Item $statement "$statement.bak_before_patch117" -Force
$src = Read-Utf8 $statement
$src = $src.Replace(
  "docText.remarkFontSize, maxLines: 6, lineHeight: 1.16);",
  "docText.remarkFontSize, maxLines: 6, lineHeight: 1.05);"
)
if ($src.Contains($oldFooter)) {
  $src = $src.Replace($oldFooter, $newFooter)
}
Write-Utf8 $statement $src
Write-Host "수정 완료: 명세서 Remark/하단문구 가독성 조정"

# ---------------------------------------------------------------------------
# 5) 공통 글자 크기 확대
# ---------------------------------------------------------------------------
$textCatalog = Join-Path $project "lib\core\document_text_catalog.dart"
Copy-Item $textCatalog "$textCatalog.bak_before_patch117" -Force
$src = Read-Utf8 $textCatalog

$oldSizes = @'
  double get footerFontSize {
    final lines = footerLines.length + 1;
    if (lines >= 5) return 12.0;
    if (lines == 4) return 13.0;
    if (lines == 3) return 14.0;
    return 15.5;
  }

  double get remarkFontSize {
    if (remark.length > 430) return 13.0;
    if (remark.length > 300) return 14.0;
    return 15.5;
  }
'@
$newSizes = @'
  double get footerFontSize {
    final lines = footerLines.length + 1;
    if (lines >= 5) return 15.5;
    if (lines == 4) return 16.5;
    if (lines == 3) return 17.5;
    return 19.0;
  }

  double get remarkFontSize {
    if (remark.length > 430) return 17.0;
    if (remark.length > 300) return 18.0;
    return 19.0;
  }
'@
$src = Replace-Required $src $oldSizes $newSizes "Remark/하단 안내문 글자 크기"
Write-Utf8 $textCatalog $src
Write-Host "수정 완료: Remark/비고 및 하단 중앙 안내문 폰트 확대"

Write-Host ""
Write-Host "Patch117 적용 완료"
Write-Host "- 상단 전체 체크 옆 '명세서 보기'만 일괄 PDF 기능"
Write-Host "- 각 항차/영수번호별 명세서 보기는 기존 기능으로 복구"
Write-Host "- 수령인 / 회사명"
Write-Host "- 무게 / 크기"
Write-Host "- 영수번호 / 구획"
Write-Host "- 값 구분자는 /"
Write-Host "- 무게는 0.0, 크기(L/W/H)는 자연수 표시"
Write-Host "- 가견적서 Remark 실제 Excel 문구 적용"
Write-Host "- Remark 및 하단 중앙 안내문 글자 확대"
Write-Host "- SQL 없음"
