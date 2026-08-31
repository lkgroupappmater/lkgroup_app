$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) {
  [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8)
}
function WriteText([string]$p,[string]$t) {
  [System.IO.File]::WriteAllText((Resolve-Path $p), $t, $utf8)
}
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# ============================================================
# 1) quotation_preview_dialog.dart
#    기타 비용은 표 본문 + 최종합계에만 반영
#    조정영역 두 번째 줄은 원래 특별할인으로 복원
# ============================================================
$p = "lib/screens/quotation_preview_dialog.dart"
$t = ReadText $p

$t = ReplaceOnce $t @'
    final extraNames =
        extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
'@ "" "quotation remove extraNames"

$t = ReplaceOnce $t @'
    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 ($extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, extraTotal > 0 ? '+${MoneyFormat.usd(extraTotal)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@ @'
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@ "quotation restore special discount"

WriteText $p $t

# ============================================================
# 2) statement_preview_dialog.dart
# ============================================================
$p = "lib/screens/statement_preview_dialog.dart"
$t = ReadText $p

$t = ReplaceOnce $t @'
    final extraNames =
        extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
'@ "" "statement remove extraNames"

$t = ReplaceOnce $t @'
    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 ($extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, extraTotal > 0 ? '+${MoneyFormat.usd(extraTotal)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@ @'
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
'@ "statement restore special discount"

WriteText $p $t

# ============================================================
# 3) cargo_management_screen.dart
#    - 기타비용 숫자 compact: +1 / +2 / +3
#    - 명세서 고정 하단 바
# ============================================================
$p = "lib/screens/cargo_management_screen.dart"
$t = ReadText $p

# 기타비용 개수 compact
$t = ReplaceOnce $t @'
                                List<String>.generate(
                                  count,
                                  (i) => '+${i + 1}',
                                ).join(' '),
'@ @'
                                '+$count',
'@ "cargo compact extra count"

# 고정 하단 명세서 선택 메서드 + 바 삽입
$anchor = @'
  @override
  Widget build(BuildContext context) => Material(
'@

$methods = @'
  Future<void> _showSelectedStatementChoice() async {
    if (_isPartner) {
      _message('협력/파트너 계정은 명세서를 조회할 수 없습니다.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _message('확인 할 고객을 선택 하시오');
      return;
    }

    final selected = _results
        .where((row) => _selectedIds.contains('${row['id']}'))
        .toList(growable: false);
    if (selected.isEmpty) {
      _message('확인 할 고객을 선택 하시오');
      return;
    }

    String receiptKey(Map<String, dynamic> row) =>
        '${row['route'] ?? ''}|${row['shipment_year'] ?? ''}|'
        '${row['voyage'] ?? ''}|${row['receipt_number'] ?? ''}';

    final receiptGroups = selected.map(receiptKey).toSet();
    final singleReceipt = receiptGroups.length == 1;

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('명세서 발급'),
        content: Text(
          singleReceipt
              ? '선택한 고객/영수번호의 명세서 발급 형식을 선택해 주세요.'
              : '복수 고객/영수번호 명세서는 PDF로만 발급됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          if (singleReceipt)
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'image'),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('이미지'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'image') {
      await _showStatement();
    } else if (choice == 'pdf') {
      await _showBatchStatementPdf();
    }
  }

  Widget _cargoFixedBottomBar() {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _results.isEmpty ? null : _toggleAllSearchResults,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _allSearchResultsSelected,
                        onChanged: _results.isEmpty
                            ? null
                            : (_) => _toggleAllSearchResults(),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text(
                        '전체',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isPartner ? null : _showSelectedStatementChoice,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('명세서'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
'@

$t = ReplaceOnce $t $anchor $methods "cargo bottom methods"

# build 함수 범위만 분리
$buildStart = $t.IndexOf("  @override`n  Widget build(BuildContext context) => Material(")
$buildEnd = $t.IndexOf("`n  String _selectedBoxPrefix()", $buildStart)
if ($buildStart -lt 0 -or $buildEnd -le $buildStart) {
  throw "안전 중단 [cargo build range]"
}
$before = $t.Substring(0,$buildStart)
$section = $t.Substring($buildStart,$buildEnd-$buildStart)
$after = $t.Substring($buildEnd)

$section = ReplaceOnce $section @'
        child: ListView(
          padding: const EdgeInsets.all(16),
'@ @'
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
'@ "cargo stack open"

# 상단 전체/명세서 버튼 제거, 제목만 유지
$section = ReplaceOnce $section @'
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '화물 정보 (${_results.length}건)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (_isManager) ...[
                    Checkbox(
                      value: _allSearchResultsSelected,
                      onChanged: _results.isEmpty
                          ? null
                          : (_) => _toggleAllSearchResults(),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text(
                      '전체',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                  if (!_isPartner)
                    TextButton.icon(
                      onPressed: _results.isEmpty ? null : _showBatchStatementPdf,
                      icon: const Icon(Icons.receipt_long_outlined, size: 17),
                      label: const Text('명세서 보기'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                ],
              ),
'@ @'
              Text(
                '화물 정보 (${_results.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
'@ "cargo remove top statement controls"

# build 종료를 Stack 종료로 변환
$oldEnd = @'
            ],
          ],
        ),
      );
'@
$newEnd = @'
            ],
          ),
            if (_searched)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _cargoFixedBottomBar(),
              ),
          ],
        ),
      );
'@
$section = ReplaceOnce $section $oldEnd $newEnd "cargo stack close"

$t = $before + $section + $after
WriteText $p $t

# ============================================================
# 4) shipment_search_screen.dart
#    전체 선택 / 운임 확인 / 화물 관리 고정 하단 바
# ============================================================
$p = "lib/screens/shipment_search_screen.dart"
$t = ReadText $p

$anchor = @'
  @override
  Widget build(BuildContext context) {
'@

$methods = @'
  Widget _searchFixedBottomBar() {
    final allSelected = _results.isNotEmpty &&
        _selectedIds.containsAll(_results.map((r) => '${r['id']}'));

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _results.isEmpty ? null : _toggleAll,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: allSelected,
                      onChanged: _results.isEmpty ? null : (_) => _toggleAll(),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text(
                      '전체',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selectedIds.isEmpty ? null : _showFreight,
                  icon: const Icon(Icons.price_check_outlined, size: 17),
                  label: const Text('운임 확인'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _selectedIds.isEmpty || widget.onManageSelected == null
                          ? null
                          : () => widget.onManageSelected!(
                                _selectedIds.toList(),
                              ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 17),
                  label: const Text('화물 관리'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
'@

$t = ReplaceOnce $t $anchor $methods "search bottom method"

$buildStart = $t.IndexOf("  @override`n  Widget build(BuildContext context) {")
$buildEnd = $t.IndexOf("`n  String _groupKey(", $buildStart)
if ($buildStart -lt 0 -or $buildEnd -le $buildStart) {
  throw "안전 중단 [search build range]"
}
$before = $t.Substring(0,$buildStart)
$section = $t.Substring($buildStart,$buildEnd-$buildStart)
$after = $t.Substring($buildEnd)

# build 내 기존 allSelected 로컬은 하단 method가 별도 계산하므로 제거
$section = ReplaceOnce $section @'
    final allSelected = _results.isNotEmpty &&
        _selectedIds.containsAll(_results.map((r) => '${r['id']}'));

'@ "" "search remove local allSelected"

$section = ReplaceOnce $section @'
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
'@ @'
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
'@ "search stack open"

# 검색 상단의 운임 확인 버튼 제거 -> 검색 버튼만 유지
$section = ReplaceOnce $section @'
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _search,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('화물 검색'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyPrimary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _selectedIds.isEmpty ? null : _showFreight,
                    icon: const Icon(Icons.price_check_outlined),
                    label: const Text('운임 확인'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
'@ @'
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search_rounded),
              label: const Text('화물 검색'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navyPrimary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
'@ "search remove top freight"

# 검색결과 상단 전체 선택/화물관리 행 제거
$section = ReplaceOnce $section @'
          if (_searched && _results.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (_) => _toggleAll(),
                  activeColor: AppColors.primary,
                ),
                const Text('전체 선택'),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _selectedIds.isEmpty || widget.onManageSelected == null
                      ? null
                      : () => widget.onManageSelected!(_selectedIds.toList()),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('화물 관리'),
                ),
              ],
            ),
          ],
'@ "" "search remove top selection row"

$oldEnd = @'
        ],
      ),
    );
  }
'@
$newEnd = @'
        ],
          ),
          if (_searched)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _searchFixedBottomBar(),
            ),
        ],
      ),
    );
  }
'@
$section = ReplaceOnce $section $oldEnd $newEnd "search stack close"

$t = $before + $section + $after
WriteText $p $t

Write-Host ""
Write-Host "Patch154 적용 완료"
Write-Host "- 가견적서/명세서 조정영역 특별할인 원복"
Write-Host "- 기타비용은 표 마지막 행 + 최종합계에만 반영"
Write-Host "- 화물관리 하단 고정: 전체 / 명세서"
Write-Host "- 단일 고객: 이미지/PDF 선택"
Write-Host "- 복수 고객: PDF만 발급 안내"
Write-Host "- 화물조회 하단 고정: 전체 / 운임 확인 / 화물 관리"
Write-Host "- 기타비용 개수 표시: +1, +2, +3 방식(현재 총 개수 1개면 +1)"
Write-Host ""
Write-Host "다음: flutter analyze"
