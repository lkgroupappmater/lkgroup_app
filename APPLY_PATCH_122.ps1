$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Backup-And-Copy($srcRel, $dstRel) {
  $src = Join-Path $Root $srcRel
  $dst = Join-Path $Root $dstRel
  if (!(Test-Path $src)) { throw "패치 파일 없음: $src" }
  if (Test-Path $dst) { Copy-Item $dst "$dst.bak_before_patch122" -Force }
  $dir = Split-Path $dst -Parent
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item $src $dst -Force
}

Backup-And-Copy "patch_files\lib\services\unknown_recipient_service.dart.txt" "lib\services\unknown_recipient_service.dart"
Backup-And-Copy "patch_files\lib\services\admin_management_status_service.dart.txt" "lib\services\admin_management_status_service.dart"
Backup-And-Copy "patch_files\lib\screens\management_menu_screen.dart.txt" "lib\screens\management_menu_screen.dart"
Backup-And-Copy "patch_files\supabase\067_unmatched_recipient_queue_and_admin_menu_badges.sql" "supabase\067_unmatched_recipient_queue_and_admin_menu_badges.sql"

$path = Join-Path $Root "lib\screens\change_approval_screen.dart"
if (!(Test-Path $path)) { throw "대상 파일 없음: $path" }
Copy-Item $path "$path.bak_before_patch122" -Force
$text = Get-Content $path -Raw -Encoding UTF8

if ($text -notmatch "_autoUnmatched") {
  $text = $text.Replace(
"  List<Map<String, dynamic>> _unknownClaims = const [];",
"  List<Map<String, dynamic>> _unknownClaims = const [];`r`n  List<Map<String, dynamic>> _autoUnmatched = const [];"
  )

  $text = $text.Replace(
"      final unknownClaims =`r`n          await UnknownRecipientService.instance.listPendingClaimsForAdmin();",
"      final unknownClaims =`r`n          await UnknownRecipientService.instance.listPendingClaimsForAdmin();`r`n      final autoUnmatched =`r`n          await UnknownRecipientService.instance.listAutoUnmatchedForAdmin();"
  )

  $text = $text.Replace(
"        _unknownClaims = unknownClaims;",
"        _unknownClaims = unknownClaims;`r`n        _autoUnmatched = autoUnmatched;"
  )

  $text = $text.Replace(
"                    if (_unknownClaims.isNotEmpty) ...[",
"                    if (_autoUnmatched.isNotEmpty) ...[`r`n                      const Text(`r`n                        '신규 업로드 · 수취인 불명 자동분류',`r`n                        style: TextStyle(`r`n                          fontSize: 16,`r`n                          fontWeight: FontWeight.bold,`r`n                          color: Colors.redAccent,`r`n                        ),`r`n                      ),`r`n                      const SizedBox(height: 4),`r`n                      const Text(`r`n                        '등록 고객의 이름/회사명 + 전화번호와 매칭되지 않은 화물입니다. 원본 항차에는 그대로 남고, 임시 영수번호 XX / 구획 F로 유지됩니다.',`r`n                        style: TextStyle(fontSize: 12),`r`n                      ),`r`n                      const SizedBox(height: 8),`r`n                      ..._autoUnmatched.map(_autoUnmatchedCard),`r`n                      const SizedBox(height: 14),`r`n                      const Divider(),`r`n                      const SizedBox(height: 8),`r`n                    ],`r`n                    if (_unknownClaims.isNotEmpty) ...["
  )

  $text = $text.Replace(
"                    if (_requests.isEmpty && _unknownClaims.isEmpty)",
"                    if (_requests.isEmpty && _unknownClaims.isEmpty && _autoUnmatched.isEmpty)"
  )

  $insert = @'
  Future<void> _resolveAutoUnmatched(Map<String, dynamic> row) async {
    final name = TextEditingController(text: '${row['consignee_name'] ?? ''}');
    final phone = TextEditingController(text: '${row['consignee_phone'] ?? ''}');
    final invoice = TextEditingController(text: '${row['invoice_number'] ?? ''}');
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');

    final save = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('수취인 불명 데이터 정상화'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      labelText: '전화번호',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: invoice,
                    decoration: const InputDecoration(
                      labelText: '송장번호',
                      border: OutlineInputBorder(),
                    ),
                  ),
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
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('수정 후 정상화'),
              ),
            ],
          ),
        ) ??
        false;

    if (save) {
      try {
        await UnknownRecipientService.instance.resolveAutoUnmatched(
          queueId: (row['queue_id'] as num).toInt(),
          consigneeName: name.text,
          consigneePhone: phone.text,
          invoiceNumber: invoice.text,
          notes: notes.text,
        );
        if (mounted) {
          _message('수취인 데이터를 정상화했습니다. 영수번호와 구획도 다시 자동 계산됩니다.');
          await _load();
        }
      } catch (error) {
        _message('수취인 데이터 정상화 실패: $error');
      }
    }

    name.dispose();
    phone.dispose();
    invoice.dispose();
    notes.dispose();
  }

  Future<void> _keepAutoUnmatched(Map<String, dynamic> row) async {
    try {
      await UnknownRecipientService.instance
          .keepAutoUnmatched((row['queue_id'] as num).toInt());
      if (!mounted) return;
      _message('수취인 불명 상태로 확인 완료했습니다. 화물은 XX / 구획 F로 유지됩니다.');
      await _load();
    } catch (error) {
      _message('처리 실패: $error');
    }
  }

  Widget _autoUnmatchedCard(Map<String, dynamic> row) {
    return Card(
      color: const Color(0xFFFFF6F6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              '${row['route'] ?? ''} · ${row['shipment_year'] ?? ''}년 · '
              '${row['voyage'] ?? ''}항차',
            ),
            const SizedBox(height: 6),
            Text('현재 수취인/회사명: ${row['consignee_name'] ?? ''}'),
            Text('현재 전화번호: ${row['consignee_phone'] ?? ''}'),
            Text(
              '임시 영수번호: ${row['receipt_number'] ?? 'XX'} · '
              '구획: ${row['unloading_zone'] ?? 'F'}',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
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

  $anchor = "  Future<void> _reviewUnknownClaim("
  $idx = $text.IndexOf($anchor)
  if ($idx -lt 0) { throw "change_approval_screen.dart 삽입 위치를 찾지 못했습니다." }
  $text = $text.Insert($idx, $insert)
}

Set-Content $path $text -Encoding UTF8

Write-Host "Patch122 적용 완료."
Write-Host "다음: Supabase SQL Editor에서 supabase/067_unmatched_recipient_queue_and_admin_menu_badges.sql 전체 실행"
Write-Host "그 후 flutter analyze"
