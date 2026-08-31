$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$cargo = Join-Path $root "lib\screens\cargo_management_screen.dart"
$approval = Join-Path $root "lib\screens\change_approval_screen.dart"
if (!(Test-Path $cargo)) { throw "파일 없음: $cargo" }
if (!(Test-Path $approval)) { throw "파일 없음: $approval" }

Copy-Item $cargo "$cargo.bak_before_patch134" -Force
Copy-Item $approval "$approval.bak_before_patch134" -Force

# ------------------------------------------------------------
# 1) Cargo Management - 삭제 대기 카드
#    최근 확정 일반 화물 카드 정보 순서와 동일하게 통일
# ------------------------------------------------------------
$s = Get-Content $cargo -Raw -Encoding UTF8

$newPending = @'
  Widget _pendingDeletionCard(Map<String, dynamic> item) {
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(item['received_at']);
    final length = _naturalNumber(item['length_cm']);
    final height = _naturalNumber(item['height_cm']);
    final width = _naturalNumber(item['width_cm']);
    final size = '$length × $height × $width cm';
    final name = '${item['consignee_name'] ?? ''}'.trim();
    final company = '${item['consignee_company'] ?? item['company_name'] ?? ''}'.trim();
    final nameCompany = company.isEmpty || company == name
        ? (name.isEmpty ? '-' : name)
        : '${name.isEmpty ? '-' : name} / $company';
    final receipt = '${item['receipt_number'] ?? ''}'.trim();
    final zone = '${item['unloading_zone'] ?? ''}'.trim();

    return Card(
      color: const Color(0xFFFFF6F6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '박스번호: ${item['box_number'] ?? ''} / 박스개수: ${quantity}개 / 입고 날짜: $receivedDate',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '삭제 대기',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _infoRow('운송 경로', '${item['route'] ?? ''}'),
            _infoRow(
              '년도 / 항차',
              '${item['shipment_year'] ?? ''} / ${_voyageLabel(item['voyage'])}',
            ),
            _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
            _infoRow('수령인 / 회사명', nameCompany),
            _infoRow('연락처', '${item['consignee_phone'] ?? ''}'),
            _infoRow(
              '무게 / 크기',
              '${_weightOneDecimal(item['weight_kg'])} kg / $size',
            ),
            _infoRow(
              '영수번호 / 구획',
              '${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _cancelDeletion(item),
                    child: const Text('삭제 취소'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _deleteNow(item),
                    child: const Text('바로 삭제'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
'@

$patternPending = '(?ms)^  Widget _pendingDeletionCard\(Map<String, dynamic> item\)[\s\S]*?(?=^  String _naturalNumber\()'
if (![regex]::IsMatch($s,$patternPending)) {
  throw "cargo_management_screen.dart: 삭제 대기 카드 위치를 찾지 못했습니다."
}
$s = [regex]::Replace($s,$patternPending,$newPending+"`r`n",1)
Set-Content $cargo $s -Encoding UTF8
Write-Host "[OK] 삭제 대기 화물 카드 -> 최근 화물 카드 구조로 통일" -ForegroundColor Green

# ------------------------------------------------------------
# 2) Change Approval - 자동 수취인 불명 카드
#    같은 화물 정보 순서/표현을 사용하되 상태/처리버튼은 유지
# ------------------------------------------------------------
$a = Get-Content $approval -Raw -Encoding UTF8

$helper = @'
  Widget _approvalCargoInfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(child: Text(value.isEmpty ? '-' : value)),
          ],
        ),
      );

  String _approvalVoyageLabel(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '-';
    return text.endsWith('항차') ? text : '$text항차';
  }

  String _approvalDateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.length >= 10 ? text.substring(0, 10) : text;
    }
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }

  String _approvalNaturalNumber(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.round().toString();
  }

  String _approvalWeight(dynamic value) {
    final number = double.tryParse('${value ?? ''}');
    return number == null ? '-' : number.toStringAsFixed(1);
  }

'@

if ($a -notmatch 'Widget _approvalCargoInfoRow') {
  $anchor = '  Widget _autoUnmatchedCard(Map<String, dynamic> row) {'
  $idx = $a.IndexOf($anchor)
  if ($idx -lt 0) { throw "change_approval_screen.dart: 자동분류 카드 위치를 찾지 못했습니다." }
  $a = $a.Insert($idx,$helper)
}

$newAuto = @'
  Widget _autoUnmatchedCard(Map<String, dynamic> row) {
    final quantity = int.tryParse('${row['quantity'] ?? ''}') ?? 1;
    final receivedDate = _approvalDateOnly(row['received_at']);
    final length = _approvalNaturalNumber(row['length_cm']);
    final height = _approvalNaturalNumber(row['height_cm']);
    final width = _approvalNaturalNumber(row['width_cm']);
    final size = '$length × $height × $width cm';
    final receipt = '${row['receipt_number'] ?? 'XX'}'.trim();
    final zone = '${row['unloading_zone'] ?? 'F'}'.trim();

    return Card(
      color: const Color(0xFFFFF6F6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '박스번호: ${row['box_number'] ?? ''} / 박스개수: ${quantity}개 / 입고 날짜: $receivedDate',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            _approvalCargoInfoRow('운송 경로', '${row['route'] ?? ''}'),
            _approvalCargoInfoRow(
              '년도 / 항차',
              '${row['shipment_year'] ?? ''} / ${_approvalVoyageLabel(row['voyage'])}',
            ),
            _approvalCargoInfoRow('송장번호', '${row['invoice_number'] ?? ''}'),
            _approvalCargoInfoRow(
              '수령인 / 회사명',
              '${row['consignee_name'] ?? ''}',
            ),
            _approvalCargoInfoRow('연락처', '${row['consignee_phone'] ?? ''}'),
            _approvalCargoInfoRow(
              '무게 / 크기',
              '${_approvalWeight(row['weight_kg'])} kg / $size',
            ),
            _approvalCargoInfoRow(
              '영수번호 / 구획',
              '${receipt.isEmpty ? 'XX' : receipt} / ${zone.isEmpty ? 'F' : zone}',
            ),
            if (row['data_locked'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '데이터 수정 잠금 상태',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _keepAutoUnmatched(row),
                  child: const Text('불명 유지'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () => _resolveAutoUnmatched(row),
                  child: const Text('확인 / 수정'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
'@

$patternAuto = '(?ms)^  Widget _autoUnmatchedCard\(Map<String, dynamic> row\) \{[\s\S]*?(?=^  Future<void> _reviewUnknownClaim\()'
if (![regex]::IsMatch($a,$patternAuto)) {
  throw "change_approval_screen.dart: 자동 수취인 불명 카드 블록을 찾지 못했습니다."
}
$a = [regex]::Replace($a,$patternAuto,$newAuto+"`r`n",1)

# Patch131 이후 실제 의미와 맞지 않는 안내문 수정
$oldDesc = '등록 고객의 이름/회사명 + 전화번호와 매칭되지 않은 화물입니다. 원본 항차에는 그대로 남고, 임시 영수번호 XX / 구획 F로 유지됩니다.'
$newDesc = '수취인 이름 또는 전화번호가 없거나, 명시적으로 수취인 불명으로 표시된 화물입니다. 확인 전에는 임시 영수번호 XX / 구획 F로 유지됩니다.'
$a = $a.Replace($oldDesc,$newDesc)

Set-Content $approval $a -Encoding UTF8
Write-Host "[OK] 수취인 불명 자동분류 카드 -> 최근 화물 카드 구조로 통일" -ForegroundColor Green
Write-Host "[OK] Patch131 기준 수취인 불명 안내문 수정" -ForegroundColor Green

Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
Write-Host "flutter run"
