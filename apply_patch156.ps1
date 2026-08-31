$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceRange([string]$text,[string]$start,[string]$end,[string]$replacement,[string]$label) {
  $s=$text.IndexOf($start)
  $e=$text.IndexOf($end,$s+$start.Length)
  if($s -lt 0 -or $e -le $s){ throw "안전 중단 [$label]" }
  return $text.Substring(0,$s)+$replacement+$text.Substring($e)
}
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count=([regex]::Matches($text,[regex]::Escape($old))).Count
  if($count -ne 1){ throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# ============================================================
# 1) Cargo management bottom bar -> 상담바 스타일
# ============================================================
$p="lib/screens/cargo_management_screen.dart"
$t=ReadText $p
$start="  Widget _cargoFixedBottomBar() {"
$end="`n  @override`n  Widget build(BuildContext context)"
$replacement=@'
  Widget _cargoFixedBottomBar() {
    final enabled = _results.isNotEmpty;
    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(22),
      color: Colors.transparent,
      shadowColor: Colors.black38,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.navyPrimary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: enabled ? _toggleAllSearchResults : null,
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _allSearchResultsSelected
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          size: 21,
                          color: enabled
                              ? AppColors.tealAccent
                              : Colors.white38,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '전체',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: enabled ? Colors.white : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withValues(alpha: .16),
                ),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: _isPartner ? null : _showSelectedStatementChoice,
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 22,
                          color: _isPartner
                              ? Colors.white38
                              : AppColors.tealAccent,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedIds.isEmpty
                              ? '명세서'
                              : '명세서 · ${_selectedIds.length}개 선택',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                _isPartner ? Colors.white38 : Colors.white,
                          ),
                        ),
                      ],
                    ),
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
$t=ReplaceRange $t $start $end $replacement "cargo consultation bar"
WriteText $p $t

# ============================================================
# 2) Excel bulk bottom bar -> 상담바 스타일
#    Patch155 적용 후 파일을 기준으로 좁게 교체
# ============================================================
$p="lib/screens/excel_bulk_management_screen.dart"
$t=ReadText $p

$old=@'
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
'@
$new=@'
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Material(
                elevation: 14,
                borderRadius: BorderRadius.circular(22),
                color: Colors.transparent,
                shadowColor: Colors.black38,
                child: Container(
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.navyPrimary,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                  child: Row(
                    children: [
                      _bulkBarAction(
                        icon: allChecked
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        label: '전체',
                        enabled: _rows.isNotEmpty && !_busy,
                        onTap: () => _toggleAll(!allChecked),
                      ),
                      _bulkBarDivider(),
                      _bulkBarAction(
                        icon: Icons.lock_outline,
                        label: '잠금',
                        enabled: _checked.isNotEmpty && !_busy,
                        onTap: () => _setLock(true),
                      ),
                      _bulkBarDivider(),
                      _bulkBarAction(
                        icon: Icons.lock_open_outlined,
                        label: '해체',
                        enabled: _checked.isNotEmpty && !_busy,
                        onTap: () => _setLock(false),
                      ),
                      _bulkBarDivider(),
                      _bulkBarAction(
                        icon: Icons.delete_outline,
                        label: '삭제',
                        enabled: _checked.isNotEmpty && !_busy,
                        onTap: _requestDeleteSelected,
                      ),
                    ],
                  ),
                ),
              ),
            ),
'@
$t=ReplaceOnce $t $old $new "excel consultation bar"

$anchor=@'
  Widget _rowCard(Map<String, dynamic> row) {
'@
$helpers=@'
  Widget _bulkBarDivider() => Container(
        width: 1,
        height: 32,
        color: Colors.white.withValues(alpha: .16),
      );

  Widget _bulkBarAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(15),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: enabled ? AppColors.tealAccent : Colors.white38,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: enabled ? Colors.white : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _rowCard(Map<String, dynamic> row) {
'@
$t=ReplaceOnce $t $anchor $helpers "excel consultation helpers"
WriteText $p $t

# ============================================================
# 3) Unknown recipient UI + admin direct edit
# ============================================================
$p="lib/screens/shipment_search_screen.dart"
$t=ReadText $p

# Admin can open same data-entry dialog; admin saves directly instead of claim.
$start="  Future<void> _claimUnknownCargo(Map<String, dynamic> row) async {"
$end="`n  Widget _unknownRecipientSection() {"
$claim=@'
  Future<void> _claimUnknownCargo(Map<String, dynamic> row) async {
    final user = widget.currentUser;
    if (user == null ||
        (user.role != UserRole.member && user.role != UserRole.admin)) {
      return;
    }
    final isAdmin = user.role == UserRole.admin;

    final name = TextEditingController(
      text: isAdmin ? '${row['consignee_name'] ?? ''}' : user.name,
    );
    final phone = TextEditingController(
      text: isAdmin ? '${row['consignee_phone'] ?? ''}' : user.phone,
    );
    final note = TextEditingController(text: '${row['notes'] ?? ''}');

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              isAdmin ? '수취인 불명 화물 정보 입력' : '본인 화물 확인 및 정정 요청',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['route'] ?? ''} / ${row['shipment_year'] ?? ''}년도 / '
                    '${_voyageLabel(row['voyage'])}\n'
                    '화물번호: ${row['box_number'] ?? ''}\n'
                    '송장번호: ${row['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: isAdmin ? '수취인 이름 / 회사명' : '본인 이름',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: isAdmin ? '연락처' : '본인 연락처',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: isAdmin ? '비고' : '확인 참고 내용 (선택)',
                      hintText: isAdmin
                          ? '필요한 경우 비고를 입력해 주세요.'
                          : '물품 내용, 발송인 등 관리자 확인에 도움이 되는 내용을 입력해 주세요.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAdmin
                        ? '관리자는 입력한 수취인 정보를 바로 반영하고 영수번호/구획을 다시 계산합니다.'
                        : '요청 승인 후 수취인 정보가 반영되며 영수번호는 해당 항차 기준으로 처리됩니다.',
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
                child: Text(isAdmin ? '수취인 정보 적용' : '본인 화물 확인 요청'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      try {
        if (isAdmin) {
          await UnknownRecipientService.instance.resolveUnknownFromSearch(
            shipmentId: '${row['id']}',
            consigneeName: name.text,
            consigneePhone: phone.text,
            notes: note.text,
          );
        } else {
          await UnknownRecipientService.instance.createClaim(
            shipmentId: '${row['id']}',
            claimantName: name.text,
            claimantPhone: phone.text,
            note: note.text,
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAdmin
                  ? '수취인 정보를 반영했습니다.'
                  : '관리자에게 본인 화물 확인 및 정정 요청을 보냈습니다.',
            ),
          ),
        );
        await _loadUnknownRecipientCargo();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAdmin
                  ? '수취인 정보 적용 실패: $error'
                  : '본인 화물 확인 요청 실패: $error',
            ),
          ),
        );
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    phone.dispose();
    note.dispose();
  }
'@
$t=ReplaceRange $t $start $end $claim "unknown claim/admin edit"

# Replace unknown section only, leave search logic untouched.
$start="  Widget _unknownRecipientSection() {"
$end="`n  Future<void> _search() async {"
$section=@'
  Widget _unknownRecipientSection() {
    if (!widget.isLoggedIn || widget.currentUser == null) {
      return const SizedBox.shrink();
    }
    final role = widget.currentUser!.role;
    final canOpen = role == UserRole.member || role == UserRole.admin;
    final isAdmin = role == UserRole.admin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.help_outline, color: AppColors.navyPrimary),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                '수취인 불명 / 데이터 불문명 화물',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: _showUnknownCargoGuide,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                '상세 안내',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isAdmin
              ? '관리자는 확인이 필요한 화물을 눌러 수취인 이름과 연락처를 바로 입력·수정할 수 있습니다.'
              : '본인 화물이 확인되면 해당 화물을 눌러 이름과 연락처를 입력하고 확인 요청할 수 있습니다.',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingUnknownRecipients)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_unknownRecipientRows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '현재 확인이 필요한 수취인 불명 화물이 없습니다.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ..._unknownRecipientRows.map((row) {
            final pending = row['claim_pending'] == true;
            final createdAt =
                DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal();
            final ageDays = createdAt == null
                ? 0
                : DateTime.now().difference(createdAt).inDays;
            final Color? warningBorder = ageDays >= 30
                ? Colors.red
                : ageDays >= 14
                    ? Colors.orange
                    : null;

            final route = '${row['route'] ?? ''}'.trim();
            final year = '${row['shipment_year'] ?? ''}'.trim();
            final voyage = _voyageLabel(row['voyage']);
            final box = '${row['box_number'] ?? ''}'.trim();
            final invoice = '${row['invoice_number'] ?? ''}'.trim();
            final name = '${row['consignee_name'] ?? ''}'.trim();
            final phone = '${row['consignee_phone'] ?? ''}'.trim();

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: warningBorder ?? const Color(0xFFE1E7EF),
                  width: warningBorder == null ? 1 : 2.2,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: canOpen && (!pending || isAdmin)
                    ? () => _claimUnknownCargo(row)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$route / ${year}년도 / $voyage',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '화물번호: ${box.isEmpty ? '-' : box}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '송장번호: ${invoice.isEmpty ? '-' : invoice}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '이름/연락처: '
                              '${name.isEmpty ? '수취인 불명' : name} / '
                              '${phone.isEmpty ? '-' : phone}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (pending && !isAdmin) ...[
                              const SizedBox(height: 6),
                              const Text(
                                '확인 요청 대기',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (canOpen && (!pending || isAdmin))
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 18),
                          child: Container(
                            width: 92,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.navyPrimary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isAdmin
                                  ? '화물을 눌러\n정보 입력/수정'
                                  : '화물을 눌러\n본인 확인 요청',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.25,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
'@
$t=ReplaceRange $t $start $end $section "unknown card redesign"
WriteText $p $t

# ============================================================
# 4) Unknown service: admin direct resolution method
# ============================================================
$p="lib/services/unknown_recipient_service.dart"
$t=ReadText $p
$anchor=@'
  Future<void> createClaim({
'@
$method=@'
  Future<void> resolveUnknownFromSearch({
    required String shipmentId,
    required String consigneeName,
    required String consigneePhone,
    String notes = '',
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId.trim());
    if (id == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client.rpc(
      'admin_resolve_unknown_recipient_from_search',
      params: {
        'p_shipment_id': id,
        'p_consignee_name': consigneeName.trim(),
        'p_consignee_phone': consigneePhone.trim(),
        'p_notes': notes.trim(),
      },
    );
  }

  Future<void> createClaim({
'@
$t=ReplaceOnce $t $anchor $method "admin unknown service method"
WriteText $p $t

Write-Host ""
Write-Host "Patch156 적용 완료"
Write-Host "- 최근 하단 고정 버튼: 상담바 스타일 통일"
Write-Host "- 수취인 불명 카드: 경로/년도/항차 큰 제목 + 화물/송장/이름연락처"
Write-Host "- 카드 우측 2줄 안내 버튼형 문구"
Write-Host "- 관리자도 수취인 불명 화물을 눌러 이름/연락처 직접 입력 가능"
Write-Host ""
Write-Host "flutter analyze 실행 후 0 error 확인"
Write-Host "그 다음 SQL 091 실행"
