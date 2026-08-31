$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text,[regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# ============================================================
# 1) Excel bulk service: 송장번호까지 RPC 전달
# ============================================================
$p="lib/services/excel_bulk_management_service.dart"
$t=ReadText $p

$t=ReplaceOnce $t @'
    required String boxNumber,
    required String senderName,
'@ @'
    required String boxNumber,
    required String invoiceNumber,
    required String senderName,
'@ "bulk service invoice argument"

$t=ReplaceOnce $t @'
        'p_box_number': boxNumber.trim(),
        'p_sender_name': senderName.trim(),
'@ @'
        'p_box_number': boxNumber.trim(),
        'p_invoice_number': invoiceNumber.trim(),
        'p_sender_name': senderName.trim(),
'@ "bulk service invoice param"

WriteText $p $t

# ============================================================
# 2) Excel bulk management screen
# ============================================================
$p="lib/screens/excel_bulk_management_screen.dart"
$t=ReadText $p

# A. receipt-group toggle helper
$anchor=@'
  Future<void> _setLock(bool locked) async {
'@
$insert=@'
  void _toggleReceiptRows(List<Map<String, dynamic>> rows) {
    final ids = rows.map((e) => '${e['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _checked.containsAll(ids)) {
        _checked.removeAll(ids);
      } else {
        _checked.addAll(ids);
      }
    });
  }

  Future<void> _setLock(bool locked) async {
'@
$t=ReplaceOnce $t $anchor $insert "bulk receipt toggle"

# B. edit dialog: invoice controller + editable field
$t=ReplaceOnce $t @'
    final box = TextEditingController(text: '${row['box_number'] ?? ''}');
    final special = TextEditingController(text: '${row['sender_name'] ?? ''}');
'@ @'
    final box = TextEditingController(text: '${row['box_number'] ?? ''}');
    final invoice =
        TextEditingController(text: '${row['invoice_number'] ?? ''}');
    final special = TextEditingController(text: '${row['sender_name'] ?? ''}');
'@ "bulk invoice controller"

$t=ReplaceOnce $t @'
                  _field(box, '박스번호'),
                  _readOnly('${row['invoice_number'] ?? ''}', '송장번호 (수정 불가)'),
'@ @'
                  _field(box, '화물번호'),
                  _field(invoice, '송장번호'),
'@ "bulk invoice field"

$t=ReplaceOnce $t @'
          boxNumber: box.text,
          senderName: special.text,
'@ @'
          boxNumber: box.text,
          invoiceNumber: invoice.text,
          senderName: special.text,
'@ "bulk invoice save"

$t=ReplaceOnce $t @'
    box.dispose();
    special.dispose();
'@ @'
    // Dialog reverse transition 종료 전에 controller를 dispose하지 않습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    box.dispose();
    invoice.dispose();
    special.dispose();
'@ "bulk delayed dispose"

# C. build() 전체를 함수 범위 기준으로 교체
$startToken="  @override`n  Widget build(BuildContext context) {"
$endToken="`n  Widget _rowCard(Map<String, dynamic> row) {"
$s=$t.IndexOf($startToken)
$e=$t.IndexOf($endToken)
if ($s -lt 0 -or $e -le $s) { throw "안전 중단 [bulk build range]" }
$before=$t.Substring(0,$s)
$after=$t.Substring($e)

$build=@'
  @override
  Widget build(BuildContext context) {
    final allChecked =
        _rows.isNotEmpty && _checked.length == _rows.length;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      grouped.putIfAbsent(
        receipt.isEmpty ? '(영수번호 없음)' : receipt,
        () => <Map<String, dynamic>>[],
      ).add(row);
    }

    int receiptTail(String value) {
      final match = RegExp(r'(\d+)\s*$').firstMatch(value);
      return match == null ? 999999 : int.tryParse(match.group(1)!) ?? 999999;
    }

    final groups = grouped.entries.toList()
      ..sort((a, b) {
        final n = receiptTail(a.key).compareTo(receiptTail(b.key));
        return n != 0 ? n : a.key.compareTo(b.key);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('엑셀 데이타 일괄 관리'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _route,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로',
                    border: OutlineInputBorder(),
                  ),
                  items: _routes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: _routeChanged,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _year,
                        decoration: const InputDecoration(
                          labelText: '년도',
                          border: OutlineInputBorder(),
                        ),
                        items: _years
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('$e년'),
                                ))
                            .toList(),
                        onChanged: _route == null ? null : _yearChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _voyage,
                        decoration: const InputDecoration(
                          labelText: '항차',
                          border: OutlineInputBorder(),
                        ),
                        items: _voyages
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text('${e}항차'),
                                ))
                            .toList(),
                        onChanged: _route == null || _year == null
                            ? null
                            : _voyageChanged,
                      ),
                    ),
                  ],
                ),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '선택 ${_checked.length}개',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _busy && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _voyage == null
                    ? const Center(
                        child: Text('운송 경로, 년도, 항차를 선택해 주세요.'),
                      )
                    : _rows.isEmpty
                        ? const Center(
                            child: Text('해당 항차 화물 데이터가 없습니다.'),
                          )
                        : ListView(
                            padding:
                                const EdgeInsets.fromLTRB(10, 8, 10, 88),
                            children: groups.expand((entry) {
                              final groupRows = entry.value;
                              final groupIds =
                                  groupRows.map((e) => '${e['id']}').toSet();
                              final groupChecked = groupIds.isNotEmpty &&
                                  _checked.containsAll(groupIds);
                              final first = groupRows.first;
                              final zone =
                                  '${first['unloading_zone'] ?? ''}'.trim();

                              return <Widget>[
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    5,
                                    4,
                                    5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: '영수번호: ',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              TextSpan(
                                                text: entry.key,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const TextSpan(
                                                text: ' / 구획: ',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              TextSpan(
                                                text:
                                                    zone.isEmpty ? '-' : zone,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const TextSpan(
                                                text: ' · 총 ',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              TextSpan(
                                                text: '${groupRows.length}개',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Checkbox(
                                        value: groupChecked,
                                        onChanged: (_) =>
                                            _toggleReceiptRows(groupRows),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                                ...groupRows.map(_rowCard),
                                const SizedBox(height: 8),
                              ];
                            }).toList(),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : Material(
              elevation: 12,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => _toggleAll(!allChecked),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: allChecked,
                              onChanged: (v) => _toggleAll(v == true),
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
                      const SizedBox(width: 4),
                      Expanded(
                        child: FilledButton(
                          onPressed: _checked.isEmpty || _busy
                              ? null
                              : () => _setLock(true),
                          child: const Text('잠금'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _checked.isEmpty || _busy
                              ? null
                              : () => _setLock(false),
                          child: const Text('해체'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _checked.isEmpty || _busy
                              ? null
                              : _requestDeleteSelected,
                          child: const Text('삭제'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
'@

$t=$before+$build+$after

# D. row card 함수 전체 교체: 카드 탭=체크, 우측 편집 아이콘
$startToken="  Widget _rowCard(Map<String, dynamic> row) {"
$endToken="`n  Widget _line(String label, dynamic value)"
$s=$t.IndexOf($startToken)
$e=$t.IndexOf($endToken)
if ($s -lt 0 -or $e -le $s) { throw "안전 중단 [bulk rowCard range]" }
$before=$t.Substring(0,$s)
$after=$t.Substring($e)

$rowCard=@'
  Widget _rowCard(Map<String, dynamic> row) {
    final id = '${row['id']}';
    final locked = row['data_locked'] == true;
    final name = '${row['consignee_name'] ?? ''}'.trim();
    final phone = '${row['consignee_phone'] ?? ''}'.trim();
    final notes = '${row['notes'] ?? ''}'.trim();

    return Card(
      margin: const EdgeInsets.only(top: 5),
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 4, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _checked.contains(id),
                onChanged: (_) => _toggle(id),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${name.isEmpty ? '-' : name} / ${phone.isEmpty ? '-' : phone}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '비고: $notes',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (locked)
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: 2),
                  child: Icon(
                    Icons.lock,
                    color: Colors.redAccent,
                    size: 17,
                  ),
                ),
              IconButton(
                tooltip: '편집',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : () => _edit(row),
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
'@
$t=$before+$rowCard+$after
WriteText $p $t

# ============================================================
# 3) Change approval: incomplete 확인/수정에 송장/영수번호
# ============================================================
$p="lib/screens/change_approval_screen.dart"
$t=ReadText $p

# _reviewIncomplete 함수 범위만 교체
$startToken="  Future<void> _reviewIncomplete("
$endToken="`n  Widget _incompleteCard("
$s=$t.IndexOf($startToken)
$e=$t.IndexOf($endToken)
if ($s -lt 0 -or $e -le $s) { throw "안전 중단 [reviewIncomplete range]" }
$before=$t.Substring(0,$s)
$after=$t.Substring($e)

$fn=@'
  Future<void> _reviewIncomplete(
    Map<String, dynamic> row, {
    required bool lock,
  }) async {
    final invoice =
        TextEditingController(text: '${row['invoice_number'] ?? ''}');
    final name =
        TextEditingController(text: '${row['consignee_name'] ?? ''}');
    final phone =
        TextEditingController(text: '${row['consignee_phone'] ?? ''}');
    final receipt =
        TextEditingController(text: '${row['receipt_number'] ?? ''}');
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');
    String? receiptWarning;

    final save = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                lock ? '확인 완료 / 데이터 잠금' : '불확실 데이터 확인 / 수정',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: invoice,
                      decoration: const InputDecoration(
                        labelText: '송장번호',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '수취인 이름 / 회사명',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phone,
                      decoration: const InputDecoration(
                        labelText: '전화번호 (없으면 비워도 됨)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: receipt,
                      decoration: const InputDecoration(
                        labelText: '영수번호',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (receiptWarning != null) {
                          setDialogState(() => receiptWarning = null);
                        }
                      },
                    ),
                    if (receiptWarning != null) ...[
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          receiptWarning!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '비고',
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
                  onPressed: () async {
                    final check = await UnknownRecipientService.instance
                        .checkReceiptNumber(
                      shipmentId:
                          '${row['shipment_id'] ?? row['id'] ?? ''}',
                      receiptNumber: receipt.text,
                    );
                    if (!context.mounted) return;
                    if (check['duplicate'] == true) {
                      final suggested =
                          '${check['suggested_receipt'] ?? ''}'.trim();
                      setDialogState(() {
                        receiptWarning = suggested.isEmpty
                            ? '이미 사용 중인 영수번호입니다.'
                            : '이미 사용 중인 영수번호입니다. 추천: $suggested';
                      });
                      if (suggested.isNotEmpty) {
                        receipt.text = suggested;
                        receipt.selection = TextSelection.fromPosition(
                          TextPosition(offset: receipt.text.length),
                        );
                      }
                      return; // 추천만 기입. 자동 저장/확정 금지.
                    }
                    if (context.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: Text(lock ? '확정 및 잠금' : '수정 저장'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (save) {
      try {
        await UnknownRecipientService.instance.reviewIncomplete(
          shipmentId: '${row['shipment_id'] ?? row['id'] ?? ''}',
          invoiceNumber: invoice.text,
          consigneeName: name.text,
          consigneePhone: phone.text,
          receiptNumber: receipt.text,
          notes: notes.text,
          lock: lock,
        );
        if (mounted) {
          _message(
            lock
                ? '불확실 데이터를 확인 완료하고 잠금했습니다.'
                : '불확실 데이터를 수정했습니다.',
          );
          await _load();
        }
      } catch (error) {
        _message('불확실 데이터 처리 실패: $error');
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    invoice.dispose();
    name.dispose();
    phone.dispose();
    receipt.dispose();
    notes.dispose();
  }
'@
$t=$before+$fn+$after
WriteText $p $t

# ============================================================
# 4) Unknown recipient service: fields + duplicate check RPC
# ============================================================
$p="lib/services/unknown_recipient_service.dart"
$t=ReadText $p

$t=ReplaceOnce $t @'
    required String shipmentId,
    required String consigneeName,
'@ @'
    required String shipmentId,
    required String invoiceNumber,
    required String consigneeName,
'@ "review incomplete invoice arg"

$t=ReplaceOnce $t @'
    required String consigneePhone,
    required String notes,
'@ @'
    required String consigneePhone,
    required String receiptNumber,
    required String notes,
'@ "review incomplete receipt arg"

$t=ReplaceOnce $t @'
        'p_shipment_id': id,
        'p_consignee_name': consigneeName.trim(),
'@ @'
        'p_shipment_id': id,
        'p_invoice_number': invoiceNumber.trim(),
        'p_consignee_name': consigneeName.trim(),
'@ "review incomplete invoice param"

$t=ReplaceOnce $t @'
        'p_consignee_phone': consigneePhone.trim(),
        'p_notes': notes.trim(),
'@ @'
        'p_consignee_phone': consigneePhone.trim(),
        'p_receipt_number': receiptNumber.trim(),
        'p_notes': notes.trim(),
'@ "review incomplete receipt param"

$anchor=@'
  Future<void> resolveAutoUnmatched({
'@
$method=@'
  Future<Map<String, dynamic>> checkReceiptNumber({
    required String shipmentId,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      return const {'duplicate': false};
    }
    final raw = await SupabaseService.client.rpc(
      'admin_check_receipt_number',
      params: {
        'p_shipment_id': shipmentId.trim(),
        'p_receipt_number': receiptNumber.trim(),
      },
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> resolveAutoUnmatched({
'@
$t=ReplaceOnce $t $anchor $method "receipt check method"
WriteText $p $t

Write-Host ""
Write-Host "Patch155 Flutter 적용 완료"
Write-Host "- Excel 일괄관리 송장번호 편집"
Write-Host "- 카드 탭=체크 / 우측 편집 버튼"
Write-Host "- 영수번호 그룹 체크"
Write-Host "- 하단 고정 전체/잠금/해체/삭제"
Write-Host "- 카드 표시 간결화"
Write-Host "- 승인관리 송장번호/영수번호 수정"
Write-Host "- 영수번호 중복 시 다음 번호 추천만 입력 (자동 확정 안함)"
Write-Host "- Dialog controller assertion 방지"
Write-Host ""
Write-Host "먼저 flutter analyze 실행"
Write-Host "SQL 090은 analyze 0 error 확인 후 실행"
