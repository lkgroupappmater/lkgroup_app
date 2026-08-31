$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# 1) 화물관리: 팝업 종료 애니메이션 중 controller dispose 충돌 방지
$cargoPath="lib/screens/cargo_management_screen.dart"
$cargo=ReadText $cargoPath
$cargo=ReplaceOnce $cargo @'
    name.dispose();
    amount.dispose();
  }

  List<Widget> _managementGroupWidgets() {
'@ @'
    // showDialog의 reverse transition이 완전히 끝난 뒤 controller를 정리합니다.
    // 즉시 dispose하면 Flutter InheritedElement의 _dependents assertion이 발생할 수 있습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    amount.dispose();
  }

  List<Widget> _managementGroupWidgets() {
'@ "cargo dialog dispose"

# 영수번호 헤더: 기타비용 버튼 옆에 +1 +2 ... 표시
$old=@'
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  IconButton(
                    tooltip: '기타 비용 (+\$)',
                    onPressed:
                        _busy ? null : () => _showReceiptExtraCostDialog(rows),
                    icon: const Icon(Icons.add_card_outlined, size: 21),
                  ),
'@
$new=@'
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  FutureBuilder<List<ExtraCostItem>>(
                    future: ReceiptExtraCostService.instance.list(
                      route: '${first['route'] ?? ''}'.trim(),
                      year: (first['shipment_year'] as num?)?.toInt() ?? 0,
                      voyage: '${first['voyage'] ?? ''}'.trim(),
                      receiptNumber: receipt,
                    ),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Text(
                                List<String>.generate(
                                  count,
                                  (i) => '+${i + 1}',
                                ).join(' '),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navyPrimary,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: '기타 비용 (+\$)',
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _showReceiptExtraCostDialog(rows);
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(
                              Icons.add_card_outlined,
                              size: 21,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
'@
$cargo=ReplaceOnce $cargo $old $new "receipt extra badge"

# 개별 화물: 하단 액션을 없애고 오른쪽 빈 공간에 편집/잠금 배치
$old=@'
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('화물번호', '${item['box_number'] ?? ''}'),
                  _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                  _infoRow('화물개수', '$quantity개'),
                  _infoRow(
                    '무게 / 크기',
                    '${_weightOneDecimal(item['weight_kg'])} kg / $size',
                  ),
                  _infoRow('입고날짜', receivedDate),
                  if (_isManager) ...[
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 12,
                        children: [
                          IconButton(
                            tooltip: '편집',
                            visualDensity: VisualDensity.compact,
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
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                          if (_isAdmin)
                            IconButton(
                              tooltip:
                                  item['data_locked'] == true ? '잠금 해제' : '잠금',
                              visualDensity: VisualDensity.compact,
                              onPressed: _busy
                                  ? null
                                  : () => _toggleShipmentLock(item),
                              icon: Icon(
                                item['data_locked'] == true
                                    ? Icons.lock
                                    : Icons.lock_open_outlined,
                                size: 19,
                                color: item['data_locked'] == true
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
'@
$new=@'
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('화물번호', '${item['box_number'] ?? ''}'),
                  _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                  _infoRow('화물개수', '$quantity개'),
                  _infoRow(
                    '무게 / 크기',
                    '${_weightOneDecimal(item['weight_kg'])} kg / $size',
                  ),
                  _infoRow('입고날짜', receivedDate),
                ],
              ),
            ),
            if (_isManager)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '편집',
                      visualDensity: VisualDensity.compact,
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
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                    if (_isAdmin)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: item['data_locked'] == true
                              ? Colors.transparent
                              : const Color(0xFF9CA3AF),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip:
                              item['data_locked'] == true ? '잠금 해제' : '잠금',
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () => _toggleShipmentLock(item),
                          icon: Icon(
                            item['data_locked'] == true
                                ? Icons.lock
                                : Icons.lock_open_outlined,
                            size: 19,
                            color: item['data_locked'] == true
                                ? Colors.red
                                : Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
'@
$cargo=ReplaceOnce $cargo $old $new "shipment action layout"
WriteText $cargoPath $cargo

# 2) 견적 기타비용: 같은 dialog reverse-transition dispose 충돌 방지
$quotePath="lib/screens/quote_request_screen.dart"
$quote=ReadText $quotePath
$quote=ReplaceOnce $quote @'
    nameController.dispose();
    amountController.dispose();
  }

  void _removeBox(int i) {
'@ @'
    // Dialog가 사라지는 애니메이션 중 controller를 먼저 dispose하지 않습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    nameController.dispose();
    amountController.dispose();
  }

  void _removeBox(int i) {
'@ "quote dialog dispose"
WriteText $quotePath $quote

# 3) 다음 작업도 같이: 불확실 고객 RPC 컬럼명을 Flutter 표준 키로 정규화
$unknownPath="lib/services/unknown_recipient_service.dart"
$unknown=ReadText $unknownPath
$old=@'
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<void> reviewIncomplete({
'@
$new=@'
    return raw.map((e) {
      final row = Map<String, dynamic>.from(e as Map);
      row['id'] ??= row['shipment_id'];
      row['reason'] ??= row['uncertainty_reason'];
      return row;
    }).toList(growable: false);
  }

  Future<void> reviewIncomplete({
'@
# 이 패턴은 listIncomplete 바로 앞/뒤 문맥으로 1회여야 함
$unknown=ReplaceOnce $unknown $old $new "approval id normalization"
WriteText $unknownPath $unknown

Write-Host ""
Write-Host "Patch149 적용 완료"
Write-Host "1. 기타비용 +1 +2 +3 표시"
Write-Host "2. 편집/잠금 아이콘 오른쪽 빈 공간으로 이동"
Write-Host "3. 잠금=빨강 / 풀림=흰색"
Write-Host "4. 견적 기타비용 Flutter assertion 방지"
Write-Host "5. 화물관리 기타비용 Flutter assertion 방지"
Write-Host "6. 다음 작업: 불확실 고객 승인 id=null 호환 수정"
Write-Host ""
Write-Host "다음: flutter analyze"
