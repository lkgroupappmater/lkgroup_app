$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

# ============================================================
# 1) cargo_management_screen.dart
# ============================================================
$path="lib/screens/cargo_management_screen.dart"
$text=ReadText $path

# A. 화물 편집 Dialog 종료 assertion 방지
$text=ReplaceOnce $text @'
    name.dispose(); phone.dispose(); notes.dispose();
    weight.dispose(); length.dispose(); width.dispose(); height.dispose();
  }

  Future<void> _deleteCheckedGroup(List<Map<String, dynamic>> rows) async {
'@ @'
    // Dialog reverse transition이 끝나기 전에 controller를 dispose하면
    // Flutter framework의 _dependents.isEmpty assertion이 발생할 수 있습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose(); phone.dispose(); notes.dispose();
    weight.dispose(); length.dispose(); width.dispose(); height.dispose();
  }

  Future<void> _deleteCheckedGroup(List<Map<String, dynamic>> rows) async {
'@ "cargo edit dialog dispose"

# B. 영수번호 그룹 헤더를 가로 Wrap 우선으로 변경
$old=@'
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(phone.isEmpty ? '-' : phone,
                          style: const TextStyle(fontSize: 12)),
                      Text(
                        '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text('총 개수: $totalQty개',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
'@
$new=@'
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(
                        phone.isEmpty ? '-' : phone,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '총 개수: $totalQty개',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
'@
$text=ReplaceOnce $text $old $new "receipt compact wrap"

# C. 삭제 대기 카드를 최신 스타일로 변환
$old=@'
  Widget _pendingDeletionCard(Map<String, dynamic> item) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '박스번호 ${item['box_number'] ?? ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyPrimary,
                ),
              ),
              const SizedBox(height: 6),
              _infoRow('운송 경로', '${item['route'] ?? ''}'),
              _infoRow('년도', '${item['shipment_year'] ?? ''}'),
              _infoRow('항차', _voyageLabel(item['voyage'])),
              _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
              _infoRow('이름', '${item['consignee_name'] ?? ''}'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => _cancelDeletion(item),
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
'@
$new=@'
  Widget _pendingDeletionCard(Map<String, dynamic> item) {
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receipt = '${item['receipt_number'] ?? ''}'.trim();
    final zone = '${item['unloading_zone'] ?? ''}'.trim();
    final phone = '${item['consignee_phone'] ?? ''}'.trim();
    final receivedDate = _dateOnly(item['received_at']);
    final length = _naturalNumber(item['length_cm']);
    final height = _naturalNumber(item['height_cm']);
    final width = _naturalNumber(item['width_cm']);
    final size = '$length × $height × $width cm';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${item['consignee_name'] ?? '-'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyPrimary,
                  ),
                ),
                Text(
                  phone.isEmpty ? '-' : phone,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${item['route'] ?? ''} · ${item['shipment_year'] ?? ''}년 · ${_voyageLabel(item['voyage'])}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _infoRow('화물번호', '${item['box_number'] ?? ''}'),
            _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
            _infoRow('화물개수', '$quantity개'),
            _infoRow(
              '무게 / 크기',
              '${_weightOneDecimal(item['weight_kg'])} kg / $size',
            ),
            _infoRow('입고날짜', receivedDate),
            const SizedBox(height: 8),
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
$text=ReplaceOnce $text $old $new "pending deletion modern card"

WriteText $path $text

# ============================================================
# 2) change_approval_screen.dart
#    변경 요청 목록에서 실제 shipment 잠금 상태를 보강
# ============================================================
$path2="lib/screens/change_approval_screen.dart"
$c=ReadText $path2

$old=@'
      final rows = await ShipmentService.instance.getPendingChangeRequests();
      final unknownClaims =
'@
$new=@'
      final rows = await ShipmentService.instance.getPendingChangeRequests();

      // 변경 요청 RPC가 data_locked를 포함하지 않는 DB 버전도 있으므로,
      // 실제 shipments 행의 현재 잠금 상태를 보강해 승인 카드에서 확실히 표시합니다.
      final shipmentIds = rows
          .map((r) => '${r['shipment_id'] ?? ''}'.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (shipmentIds.isNotEmpty) {
        final shipmentRows =
            await ShipmentService.instance.getRowsByIds(shipmentIds);
        final lockedById = <String, bool>{
          for (final shipment in shipmentRows)
            '${shipment['id']}': shipment['data_locked'] == true,
        };
        for (final row in rows) {
          final shipmentId = '${row['shipment_id'] ?? ''}'.trim();
          if (shipmentId.isNotEmpty && lockedById.containsKey(shipmentId)) {
            row['data_locked'] = lockedById[shipmentId];
          }
        }
      }

      final unknownClaims =
'@
$c=ReplaceOnce $c $old $new "change approval lock enrichment"

# 기존 잠금 표시 문구를 더 짧고 명확하게
$c=$c.Replace("'데이터 수정 잠금된 화물'", "'🔒 현재 잠금 상태'")

WriteText $path2 $c

Write-Host ""
Write-Host "Patch151 적용 완료"
Write-Host "- 화물 1건 편집 Dialog assertion 수정"
Write-Host "- 변경 승인 카드에서 실제 현재 잠금 상태 보강/표시"
Write-Host "- 화물 삭제 대기 카드 최신 구조로 변경"
Write-Host "- 영수번호 그룹 헤더 Wrap 가로 우선 배치"
Write-Host ""
Write-Host "다음: flutter analyze"
