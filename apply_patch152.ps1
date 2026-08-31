$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) {
  [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8)
}
function WriteText([string]$p,[string]$t) {
  [System.IO.File]::WriteAllText((Resolve-Path $p), $t, $utf8)
}
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# ============================================================
# 1) cargo_management_screen.dart
# ============================================================
$path = "lib/screens/cargo_management_screen.dart"
$text = ReadText $path

# ------------------------------------------------------------
# A. 영수번호/고객 단위 편집 + 개별 화물 중량/크기 전용 편집 메서드 삽입
# ------------------------------------------------------------
$anchor = @'
  Future<void> _showGroupStatement(List<Map<String, dynamic>> rows) async {
'@

$methods = @'
  Future<void> _editReceiptGroupCustomer(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty || !(_isAdmin || _isStaff)) return;

    final first = rows.first;
    final name = TextEditingController(
      text: '${first['consignee_name'] ?? ''}',
    );
    final phone = TextEditingController(
      text: '${first['consignee_phone'] ?? ''}',
    );
    final notes = TextEditingController(
      text: '${first['notes'] ?? ''}',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${first['receipt_number'] ?? ''} 고객 정보 편집',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: '이름 / 회사명',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '연락처',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '기타 내용',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '이 영수번호에 묶인 ${rows.length}개 화물에 동일하게 적용됩니다.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('일괄 저장'),
          ),
        ],
      ),
    );

    if (save == true) {
      final changes = <String, dynamic>{
        'consignee_name': name.text.trim(),
        'consignee_phone': phone.text.trim(),
        'notes': notes.text.trim(),
      };

      setState(() => _busy = true);
      try {
        for (final row in rows) {
          await ShipmentService.instance.updateRow(
            '${row['id']}',
            changes,
          );
        }
        if (mounted) {
          _message('${rows.length}개 화물의 고객 정보를 수정했습니다.');
          await _search();
        }
      } catch (error) {
        _message('고객 단위 편집 실패: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    phone.dispose();
    notes.dispose();
  }

  Future<void> _editCargoMeasurements(
    Map<String, dynamic> item,
  ) async {
    final weight = TextEditingController(
      text: '${item['weight_kg'] ?? ''}',
    );
    final length = TextEditingController(
      text: '${item['length_cm'] ?? ''}',
    );
    final width = TextEditingController(
      text: '${item['width_cm'] ?? ''}',
    );
    final height = TextEditingController(
      text: '${item['height_cm'] ?? ''}',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${item['box_number'] ?? ''} 중량 / 크기 편집'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '중량 (kg)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: length,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '가로 (cm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: width,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '세로 (cm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: height,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '높이 (cm)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (save == true) {
      num? n(String value) =>
          value.trim().isEmpty ? null : num.tryParse(value.trim());

      final changes = <String, dynamic>{
        'weight_kg': n(weight.text),
        'length_cm': n(length.text),
        'width_cm': n(width.text),
        'height_cm': n(height.text),
      };

      setState(() => _busy = true);
      try {
        await ShipmentService.instance.updateRow(
          '${item['id']}',
          changes,
        );
        if (mounted) {
          _message('중량 / 크기 정보를 저장했습니다.');
          await _search();
        }
      } catch (error) {
        _message('중량 / 크기 편집 실패: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    weight.dispose();
    length.dispose();
    width.dispose();
    height.dispose();
  }

  Future<void> _showGroupStatement(List<Map<String, dynamic>> rows) async {
'@

$text = ReplaceOnce $text $anchor $methods "new edit methods"

# ------------------------------------------------------------
# B. 영수번호 그룹 헤더: 영수번호/구획, 총개수도 이름과 동일 강조
# ------------------------------------------------------------
$text = ReplaceOnce $text @'
                      Text(
                        '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '총 개수: $totalQty개',
                        style: const TextStyle(fontSize: 12),
                      ),
'@ @'
                      Text(
                        '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(
                        '총 개수: $totalQty개',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
'@ "receipt header emphasis"

# ------------------------------------------------------------
# C. 기타비용 아이콘 앞에 고객단위 편집 버튼 추가
# ------------------------------------------------------------
$text = ReplaceOnce $text @'
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  FutureBuilder<List<ExtraCostItem>>(
'@ @'
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  IconButton(
                    tooltip: '고객 단위 편집',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy
                        ? null
                        : () => _editReceiptGroupCustomer(rows),
                    icon: const Icon(Icons.edit_note_outlined, size: 20),
                  ),
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  FutureBuilder<List<ExtraCostItem>>(
'@ "receipt group edit button"

# ------------------------------------------------------------
# D. 개별 화물 편집 버튼은 중량/크기만
# ------------------------------------------------------------
$old = @'
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _selectedIds
                                  ..clear()
                                  ..add(id);
                              });
                              await _editCheckedGroup([item]);
                            },
'@
$new = @'
                      onPressed: _busy
                          ? null
                          : () => _editCargoMeasurements(item),
'@
$text = ReplaceOnce $text $old $new "single cargo measurement edit"

WriteText $path $text

# ============================================================
# 2) change_approval_screen.dart
# ============================================================
$path2 = "lib/screens/change_approval_screen.dart"
$c = ReadText $path2

# ------------------------------------------------------------
# E. 불확실 데이터 카드: 확인/수정, 확정/잠금 버튼을 우측 상단으로 이동
# ------------------------------------------------------------
$old = @'
            Text(
              '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
'@
$new = @'
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    OutlinedButton(
                      onPressed: () => _reviewIncomplete(row, lock: false),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      child: const Text(
                        '확인/수정',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _reviewIncomplete(row, lock: true),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      icon: const Icon(Icons.lock_outline, size: 14),
                      label: const Text(
                        '확정/잠금',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
'@
# _incompleteCard의 첫 box title만 대상으로 1회여야 함.
$c = ReplaceOnce $c $old $new "incomplete top actions"

# 하단 기존 버튼 Row 제거
$c = ReplaceOnce $c @'
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _reviewIncomplete(row, lock: false),
                  child: const Text('확인 / 수정'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => _reviewIncomplete(row, lock: true),
                  icon: const Icon(Icons.lock_outline, size: 17),
                  label: const Text('확정 / 잠금'),
                ),
              ],
            ),
'@ @'
            const SizedBox(height: 4),
'@ "remove incomplete bottom actions"

# ------------------------------------------------------------
# F. 일반 변경승인 요청 카드: 잠긴 화물은 상단 우측 빨간 잠금 배지로 명확히
# ------------------------------------------------------------
$c = ReplaceOnce $c @'
                Expanded(
                  child: Text(
                    '${r['box_number'] ?? ''} · ${r['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
'@ @'
                Expanded(
                  child: Text(
                    '${r['box_number'] ?? ''} · ${r['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (r['data_locked'] == true)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5E5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock,
                          size: 13,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 3),
                        Text(
                          '잠금',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
'@ "request lock badge"

WriteText $path2 $c

Write-Host ""
Write-Host "Patch152 적용 완료"
Write-Host "- 영수번호 그룹에 고객단위 편집 버튼 추가"
Write-Host "- 고객단위 편집: 이름/연락처/기타내용 일괄 수정"
Write-Host "- 영수번호/구획, 총개수 강조 스타일 통일"
Write-Host "- 개별 화물 편집: 중량/크기만 표시"
Write-Host "- 확인/수정, 확정/잠금 버튼 우측 상단 이동"
Write-Host "- 변경승인 잠긴 화물 상단 빨간 잠금 배지 추가"
Write-Host ""
Write-Host "다음: flutter analyze"
