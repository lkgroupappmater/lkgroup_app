$ErrorActionPreference = 'Stop'

# ============================================================
# shipment_search_screen.dart
# - 일반회원 화물 조회 하단에 수취인 불명 화물 카드
# - 본인 화물 확인 및 정정 요청
# ============================================================
$path = "lib/screens/shipment_search_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("import '../services/unknown_recipient_service.dart';")) {
  $needle = "import '../services/shipment_service.dart';"
  if (!$text.Contains($needle)) { throw "shipment_search import anchor not found" }
  $text = $text.Replace(
    $needle,
    "$needle`r`nimport '../services/unknown_recipient_service.dart';"
  )
}

if (!$text.Contains("List<Map<String, dynamic>> _unknownRecipientRows")) {
  $needle = "  List<Map<String, dynamic>> _results = [];"
  $replacement = @'
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _unknownRecipientRows = const [];
  bool _loadingUnknownRecipients = false;
'@
  if (!$text.Contains($needle)) { throw "shipment_search state anchor not found" }
  $text = $text.Replace($needle, $replacement.TrimEnd())
}

if (!$text.Contains("_loadUnknownRecipientCargo();")) {
  $needle = "    _prefillMemberFields();"
  # initState와 didUpdateWidget 양쪽에 들어가도 안전하게 첫 2곳만 교체.
  $text = $text.Replace(
    $needle,
    "$needle`r`n    _loadUnknownRecipientCargo();"
  )
}

if (!$text.Contains("Future<void> _loadUnknownRecipientCargo()")) {
  $needle = "  Future<void> _search() async {"
  $method = @'
  Future<void> _loadUnknownRecipientCargo() async {
    final user = widget.currentUser;
    if (!widget.isLoggedIn || user == null || user.role != UserRole.member) {
      if (mounted) {
        setState(() => _unknownRecipientRows = const []);
      }
      return;
    }

    if (mounted) setState(() => _loadingUnknownRecipients = true);
    try {
      final rows =
          await UnknownRecipientService.instance.listVisibleUnknownCargo();
      if (!mounted) return;
      setState(() => _unknownRecipientRows = rows);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수취인 불명 화물 조회 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingUnknownRecipients = false);
    }
  }

  Future<void> _claimUnknownCargo(Map<String, dynamic> row) async {
    final user = widget.currentUser;
    if (user == null || user.role != UserRole.member) return;

    final name = TextEditingController(text: user.name);
    final phone = TextEditingController(text: user.phone);
    final note = TextEditingController();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('본인 화물 확인 및 정정 요청'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['route'] ?? ''} · ${row['shipment_year'] ?? ''}년 · '
                    '${_voyageLabel(row['voyage'])}\n'
                    '박스번호 ${row['box_number'] ?? ''}\n'
                    '송장번호 ${row['invoice_number'] ?? ''}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: '본인 이름',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '본인 연락처',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '확인 참고 내용 (선택)',
                      hintText: '물품 내용, 발송인 등 관리자 확인에 도움이 되는 내용을 입력해 주세요.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '요청 승인 후 이름은 "수취인 불명 / 고객 이름" 형태로 기록되며, '
                    '영수번호는 해당 항차의 마지막 영수번호 다음 번호로 자동 부여됩니다.',
                    style: TextStyle(
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
                child: const Text('본인 화물 확인 및 정정 요청'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      try {
        await UnknownRecipientService.instance.createClaim(
          shipmentId: '${row['id']}',
          claimantName: name.text,
          claimantPhone: phone.text,
          note: note.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('관리자에게 본인 화물 확인 및 정정 요청을 보냈습니다.'),
          ),
        );
        await _loadUnknownRecipientCargo();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('본인 화물 확인 요청 실패: $error')),
        );
      }
    }

    name.dispose();
    phone.dispose();
    note.dispose();
  }

  Widget _unknownRecipientSection() {
    if (widget.currentUser?.role != UserRole.member) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        const Row(
          children: [
            Icon(Icons.help_outline, color: AppColors.navyPrimary),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                '수취인 불명 / 데이터 불문명 화물',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '수취인을 특정할 수 없는 화물만 모든 일반 회원에게 제한된 정보로 표시됩니다. '
          '본인 화물이 확인되면 해당 카드를 눌러 정정 요청해 주세요.',
          style: TextStyle(
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
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: pending ? null : () => _claimUnknownCargo(row),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '박스번호 ${row['box_number'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          ),
                          if (pending)
                            const Text(
                              '확인 요청 대기',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _row('운송 경로', '${row['route'] ?? ''}'),
                      _row('년도', '${row['shipment_year'] ?? ''}'),
                      _row('항차', _voyageLabel(row['voyage'])),
                      _row('송장번호', '${row['invoice_number'] ?? ''}'),
                      _row(
                        '수취인',
                        '${row['consignee_name'] ?? '수취인 불명'}',
                      ),
                      _row(
                        '연락처',
                        '${row['consignee_phone'] ?? ''}',
                      ),
                      if (!pending) ...[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '카드를 눌러 본인 화물 확인 요청',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
  if (!$text.Contains($needle)) { throw "shipment_search method anchor not found" }
  $text = $text.Replace($needle, $method + $needle)
}

if (!$text.Contains("_unknownRecipientSection(),")) {
  $needle = @'
          if (!_canSeeAll && _searched)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '일반 회원은 송장번호 뒤 4자리 이상, 정확한 이름 또는 연락처 뒤 8자리 기준으로 조회됩니다.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
'@
  $replacement = $needle + @'
          _unknownRecipientSection(),
'@
  if (!$text.Contains($needle)) { throw "shipment_search bottom anchor not found" }
  $text = $text.Replace($needle, $replacement)
}

Set-Content -Path $path -Value $text -Encoding UTF8


# ============================================================
# change_approval_screen.dart
# - 기존 화물 변경 승인 화면에 수취인 불명 확인요청 섹션 추가
# ============================================================
$path = "lib/screens/change_approval_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("import '../services/unknown_recipient_service.dart';")) {
  $needle = "import '../services/shipment_service.dart';"
  if (!$text.Contains($needle)) { throw "change approval import anchor not found" }
  $text = $text.Replace(
    $needle,
    "$needle`r`nimport '../services/unknown_recipient_service.dart';"
  )
}

if (!$text.Contains("List<Map<String, dynamic>> _unknownClaims")) {
  $needle = "  List<Map<String, dynamic>> _requests = const [];"
  $replacement = @'
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _unknownClaims = const [];
'@
  $text = $text.Replace($needle, $replacement.TrimEnd())
}

if (!$text.Contains("listPendingClaimsForAdmin")) {
  $needle = @'
      final rows = await ShipmentService.instance.getPendingChangeRequests();
      if (!mounted) return;
      setState(() {
        _requests = rows;
'@
  $replacement = @'
      final rows = await ShipmentService.instance.getPendingChangeRequests();
      final unknownClaims =
          await UnknownRecipientService.instance.listPendingClaimsForAdmin();
      if (!mounted) return;
      setState(() {
        _requests = rows;
        _unknownClaims = unknownClaims;
'@
  if (!$text.Contains($needle)) { throw "change approval load anchor not found" }
  $text = $text.Replace($needle, $replacement)
}

if (!$text.Contains("Future<void> _reviewUnknownClaim")) {
  $needle = "  Future<void> _bulk(String action) async {"
  $method = @'
  Future<void> _reviewUnknownClaim(
    Map<String, dynamic> claim,
    String action,
  ) async {
    final id = (claim['claim_id'] as num).toInt();
    final approve = action == 'approve';

    if (approve) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('수취인 불명 화물 확인 승인'),
              content: Text(
                '이 요청을 승인하면:\n'
                '이름: 수취인 불명 / ${claim['claimant_name'] ?? ''}\n'
                '연락처: ${claim['claimant_phone'] ?? ''}\n'
                '영수번호: 해당 항차 마지막 영수번호 다음 번호\n\n'
                '으로 반영됩니다.'
                '${claim['data_locked'] == true ? '\n\n데이터 잠금은 승인 후에도 유지됩니다.' : ''}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('확인 및 승인'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }

    try {
      await UnknownRecipientService.instance.reviewClaim(
        claimId: id,
        action: action,
      );
      if (!mounted) return;
      _message(approve
          ? '수취인 불명 화물을 본인 화물로 확인 승인했습니다.'
          : '수취인 불명 화물 확인 요청을 거절했습니다.');
      await _load();
    } catch (error) {
      _message('수취인 불명 화물 요청 처리 실패: $error');
    }
  }

  Widget _unknownClaimCard(Map<String, dynamic> claim) {
    return Card(
      color: const Color(0xFFFFFBF2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.help_outline, color: Colors.orange),
                SizedBox(width: 6),
                Text(
                  '수취인 불명 · 본인 화물 확인 요청',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${claim['box_number'] ?? ''} · ${claim['invoice_number'] ?? ''}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              '${claim['route'] ?? ''} · ${claim['shipment_year'] ?? ''}년 · '
              '${claim['voyage'] ?? ''}항차',
            ),
            const SizedBox(height: 6),
            Text('현재 이름: ${claim['current_unknown_name'] ?? ''}'),
            Text('현재 연락처: ${claim['current_unknown_phone'] ?? ''}'),
            const Divider(height: 20),
            Text(
              '요청 회원: ${claim['claimant_name'] ?? ''} '
              '(${claim['requester_email'] ?? ''})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('요청 연락처: ${claim['claimant_phone'] ?? ''}'),
            if ('${claim['note'] ?? ''}'.trim().isNotEmpty)
              Text('확인 참고 내용: ${claim['note']}'),
            if (claim['data_locked'] == true) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock, size: 16, color: Colors.redAccent),
                  SizedBox(width: 5),
                  Text(
                    '데이터 수정 잠금된 화물',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _reviewUnknownClaim(claim, 'reject'),
                  child: const Text('거절'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () => _reviewUnknownClaim(claim, 'approve'),
                  child: const Text('본인 화물 확인 승인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

'@
  if (!$text.Contains($needle)) { throw "change approval method anchor not found" }
  $text = $text.Replace($needle, $method + $needle)
}

if (!$text.Contains("..._unknownClaims.map(_unknownClaimCard)")) {
  $needle = @'
                  children: [
                    if (_requests.isEmpty)
'@
  $replacement = @'
                  children: [
                    if (_unknownClaims.isNotEmpty) ...[
                      const Text(
                        '수취인 불명 화물 확인 요청',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._unknownClaims.map(_unknownClaimCard),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    if (_requests.isEmpty && _unknownClaims.isEmpty)
'@
  if (!$text.Contains($needle)) { throw "change approval list anchor not found" }
  $text = $text.Replace($needle, $replacement)

  # 기존 else는 _requests 기준이어야 함. unknown claim만 있고 normal request가 없을 때
  # 전체선택 UI가 나타나지 않도록 기존 "else ...[" 조건을 명시적으로 변경.
  $text = $text.Replace(
    "                    else ...[",
    "                    if (_requests.isNotEmpty) ...["
  )
}

Set-Content -Path $path -Value $text -Encoding UTF8

Write-Host "PHASE 3B Dart patch complete"
