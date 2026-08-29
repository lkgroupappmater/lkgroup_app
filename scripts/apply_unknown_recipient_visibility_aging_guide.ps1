$ErrorActionPreference = 'Stop'
$path = "lib/screens/shipment_search_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }
$text = Get-Content -Raw -Encoding UTF8 $path

# 1) 모든 로그인 가입자에게 수취인 불명 목록 로드
$old = @'
    if (!widget.isLoggedIn || user == null || user.role != UserRole.member) {
'@
$new = @'
    if (!widget.isLoggedIn || user == null) {
'@
if ($text.Contains($old)) {
  $text = $text.Replace($old, $new)
}

# 2) 상세 안내 팝업 메서드 추가
if (!$text.Contains("void _showUnknownCargoGuide()")) {
  $anchor = "  Future<void> _claimUnknownCargo(Map<String, dynamic> row) async {"
  if (!$text.Contains($anchor)) { throw "unknown claim method anchor not found" }

  $method = @'
  void _showUnknownCargoGuide() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '수취인 불명 화물 보관·처분 상세 안내',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          '• 물품 도착 및 출고 후 특별한 사유 없이 장기 미수취 물품의 경우 '
          '보관료등 기타 추가 비용이 발생 할 수 있습니다.\n\n'
          '• 물품 출고 후 1주 후부터 보관료(최소 3불/CBM/day)가 발생하며, '
          '특별한 사유 없이 2달 이상 보관 물품들은 임의로 폐기/처분 될 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

'@
  $text = $text.Replace($anchor, $method + $anchor)
}

# 3) 섹션 표시를 일반회원만 -> 모든 로그인 가입자로 변경
$old = @'
  Widget _unknownRecipientSection() {
    if (widget.currentUser?.role != UserRole.member) {
      return const SizedBox.shrink();
    }
'@
$new = @'
  Widget _unknownRecipientSection() {
    if (!widget.isLoggedIn || widget.currentUser == null) {
      return const SizedBox.shrink();
    }
    final canClaim = widget.currentUser?.role == UserRole.member;
'@
if (!$text.Contains($old) -and !$text.Contains("final canClaim = widget.currentUser?.role == UserRole.member;")) {
  throw "unknown recipient section role anchor not found"
}
$text = $text.Replace($old, $new)

# 4) 제목 Row에 상세 안내 버튼 추가
$old = @'
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
'@
$new = @'
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
'@
if ($text.Contains($old)) {
  $text = $text.Replace($old, $new)
} elseif (!$text.Contains("onPressed: _showUnknownCargoGuide")) {
  throw "unknown recipient title row anchor not found"
}

# 5) 안내문: 일반회원 한정 표현 제거
$old = @'
          '수취인을 특정할 수 없는 화물만 모든 일반 회원에게 제한된 정보로 표시됩니다. '
          '본인 화물이 확인되면 해당 카드를 눌러 정정 요청해 주세요.',
'@
$new = @'
          '수취인을 특정할 수 없는 화물은 로그인한 가입자에게 제한된 정보로 표시됩니다. '
          '일반 회원은 본인 화물이 확인되면 해당 카드를 눌러 정정 요청할 수 있습니다.',
'@
$text = $text.Replace($old, $new)

# 6) 카드 생성부: 데이터 입력일 기준 14일/30일 경고 테두리
$old = @'
          ..._unknownRecipientRows.map((row) {
            final pending = row['claim_pending'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: pending ? null : () => _claimUnknownCargo(row),
'@
$new = @'
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

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: warningBorder == null
                  ? null
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: warningBorder,
                        width: 2.2,
                      ),
                    ),
              child: InkWell(
                onTap: canClaim && !pending
                    ? () => _claimUnknownCargo(row)
                    : null,
'@
if (!$text.Contains($old) -and !$text.Contains("final Color? warningBorder = ageDays >= 30")) {
  throw "unknown recipient card anchor not found"
}
$text = $text.Replace($old, $new)

# 7) 카드 하단 클릭 안내는 일반회원만
$old = @'
                      if (!pending) ...[
'@
$new = @'
                      if (canClaim && !pending) ...[
'@
# 해당 토큰은 unknown section에 한 번 존재하는 구조 기준. 첫 occurrence만 교체.
$idx = $text.IndexOf($old, $text.IndexOf("Widget _unknownRecipientSection()"))
if ($idx -ge 0) {
  $text = $text.Substring(0,$idx) + $new + $text.Substring($idx + $old.Length)
}

Set-Content -Path $path -Value $text -Encoding UTF8
Write-Host "수취인 불명 화물 노출/상세안내/장기방치 경고 패치 완료."
Write-Host "다음: Supabase 048 SQL 실행 후 flutter analyze"
