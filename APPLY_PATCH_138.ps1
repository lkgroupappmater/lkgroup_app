$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$import = Join-Path $root "lib\services\excel_import_service.dart"
$queue = Join-Path $root "lib\services\excel_import_queue_service.dart"
$upload = Join-Path $root "lib\screens\excel_upload_screen.dart"
$unknown = Join-Path $root "lib\services\unknown_recipient_service.dart"
$approval = Join-Path $root "lib\screens\change_approval_screen.dart"

foreach ($p in @($import,$queue,$upload,$unknown,$approval)) {
  if (!(Test-Path $p)) { throw "파일 없음: $p" }
  Copy-Item $p "$p.bak_before_patch138" -Force
}

# ------------------------------------------------------------------
# 1. ExcelImportService: 실제 단계별 progress callback
# ------------------------------------------------------------------
$s = Get-Content $import -Raw -Encoding UTF8

$oldSig = @'
  Future<ExcelImportResult> importBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final workbook = _readRawWorkbook(bytes);
'@
$newSig = @'
  Future<ExcelImportResult> importBytes(
    Uint8List bytes, {
    required String fileName,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.12, 'Excel 구조 확인 중');
    final workbook = _readRawWorkbook(bytes);
    onProgress?.call(0.25, '화물 행 분석 중');
'@
if (!$s.Contains($oldSig)) { throw "excel_import_service.dart: importBytes 시그니처를 찾지 못했습니다." }
$s = $s.Replace($oldSig,$newSig)

$oldUpsert = "    final inserted = await ShipmentService.instance.upsertFromRows(uniqueRows);"
$newUpsert = @'
    onProgress?.call(0.45, '중복 정리 완료 · 화물 DB 반영 중');
    final inserted = await ShipmentService.instance.upsertFromRows(uniqueRows);
    onProgress?.call(0.72, '화물 DB 반영 완료 · 고객 규칙 확인 중');
'@
if (!$s.Contains($oldUpsert)) { throw "excel_import_service.dart: Patch137 upsert 위치를 찾지 못했습니다." }
$s = $s.Replace($oldUpsert,$newUpsert)

$oldDiscount = @'
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);

    if (SupabaseConfig.isConfigured) {
'@
$newDiscount = @'
    final customerRuleResult =
        await _importCustomerDiscountRules(workbook, routeKey: routeKey);
    onProgress?.call(0.86, '고객 규칙 확인 완료 · 원본 Excel 보관 중');

    if (SupabaseConfig.isConfigured) {
'@
if (!$s.Contains($oldDiscount)) { throw "excel_import_service.dart: 할인 처리 위치를 찾지 못했습니다." }
$s = $s.Replace($oldDiscount,$newDiscount)

$oldNoCargo = "    final noCargoSheet ="
$newNoCargo = @'
    onProgress?.call(0.96, '최종 정리 중');

    final noCargoSheet =
'@
if (!$s.Contains($oldNoCargo)) { throw "excel_import_service.dart: 완료 직전 위치를 찾지 못했습니다." }
$s = $s.Replace($oldNoCargo,$newNoCargo)

Set-Content $import $s -Encoding UTF8

# ------------------------------------------------------------------
# 2. QueueService: progress callback 연결
# ------------------------------------------------------------------
$q = Get-Content $queue -Raw -Encoding UTF8
$oldCall = @'
          final result = await ExcelImportService.instance.importBytes(
            next.bytes,
            fileName: next.fileName,
          );
'@
$newCall = @'
          final result = await ExcelImportService.instance.importBytes(
            next.bytes,
            fileName: next.fileName,
            onProgress: (progress, message) {
              next!.progress = progress;
              next.message = '${(progress * 100).round()}% · $message';
              notifyListeners();
            },
          );
'@
if (!$q.Contains($oldCall)) { throw "excel_import_queue_service.dart: Patch137 importBytes 호출을 찾지 못했습니다." }
$q = $q.Replace($oldCall,$newCall)

# processing 시작값도 12%로
$q = $q.Replace("        next.progress = 0.35;`r`n        next.message = 'Excel 분석 · 중복 정리 · DB 반영 중';",
                "        next.progress = 0.12;`r`n        next.message = '12% · Excel 구조 확인 중';")
$q = $q.Replace("        next.progress = 0.35;`n        next.message = 'Excel 분석 · 중복 정리 · DB 반영 중';",
                "        next.progress = 0.12;`n        next.message = '12% · Excel 구조 확인 중';")
Set-Content $queue $q -Encoding UTF8

# ------------------------------------------------------------------
# 3. Upload screen: determinate bar + 숫자 %
# ------------------------------------------------------------------
$u = Get-Content $upload -Raw -Encoding UTF8
$u = $u.Replace(
"            LinearProgressIndicator(`r`n              value: working ? null : job.progress,`r`n              minHeight: 8,`r`n            ),",
"            LinearProgressIndicator(`r`n              value: job.progress,`r`n              minHeight: 8,`r`n            ),")
$u = $u.Replace(
"            LinearProgressIndicator(`n              value: working ? null : job.progress,`n              minHeight: 8,`n            ),",
"            LinearProgressIndicator(`n              value: job.progress,`n              minHeight: 8,`n            ),")

# unused local working 제거
$u = $u.Replace("    final working = job.status == ExcelImportJobStatus.processing;`r`n","")
$u = $u.Replace("    final working = job.status == ExcelImportJobStatus.processing;`n","")

# 상태 우측에도 processing percentage 표시
$oldStatus = "_statusText(job.status),"
$newStatus = "job.status == ExcelImportJobStatus.processing`r`n                      ? '${(job.progress * 100).round()}% 진행중'`r`n                      : _statusText(job.status),"
if ($u.Contains($oldStatus)) { $u = $u.Replace($oldStatus,$newStatus) }
Set-Content $upload $u -Encoding UTF8

# ------------------------------------------------------------------
# 4. UnknownRecipientService: incomplete review RPC 추가
# ------------------------------------------------------------------
$n = Get-Content $unknown -Raw -Encoding UTF8
$anchor = @'
  Future<void> resolveAutoUnmatched({
'@
$methods = @'
  Future<List<Map<String, dynamic>>> listIncompleteForAdmin() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw =
        await SupabaseService.client.rpc('admin_list_incomplete_shipments')
            as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<void> reviewIncomplete({
    required String shipmentId,
    required String consigneeName,
    required String consigneePhone,
    required String notes,
    required bool lock,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId);
    if (id == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client.rpc(
      'admin_review_incomplete_shipment',
      params: {
        'p_shipment_id': id,
        'p_consignee_name': consigneeName.trim(),
        'p_consignee_phone': consigneePhone.trim(),
        'p_notes': notes.trim(),
        'p_lock': lock,
      },
    );
  }

'@
if (!$n.Contains($anchor)) { throw "unknown_recipient_service.dart: 삽입 위치를 찾지 못했습니다." }
if (!$n.Contains("listIncompleteForAdmin")) { $n = $n.Replace($anchor,$methods+$anchor) }
Set-Content $unknown $n -Encoding UTF8

# ------------------------------------------------------------------
# 5. ChangeApprovalScreen: 이름만/전화없음 별도 확인 목록 + 잠금확정
#    넓은 정규식 치환 금지. 정확한 작은 anchor만 사용.
# ------------------------------------------------------------------
$a = Get-Content $approval -Raw -Encoding UTF8

$stateAnchor = "  List<Map<String, dynamic>> _autoUnmatched = const [];"
if (!$a.Contains($stateAnchor)) { throw "change_approval_screen.dart: state anchor 없음" }
$a = $a.Replace($stateAnchor,$stateAnchor+"`r`n  List<Map<String, dynamic>> _incomplete = const [];")

$loadAnchor = @'
      final autoUnmatched =
          await UnknownRecipientService.instance.listAutoUnmatchedForAdmin();
'@
$loadNew = @'
      final autoUnmatched =
          await UnknownRecipientService.instance.listAutoUnmatchedForAdmin();
      final incomplete =
          await UnknownRecipientService.instance.listIncompleteForAdmin();
'@
if (!$a.Contains($loadAnchor)) { throw "change_approval_screen.dart: load anchor 없음" }
$a = $a.Replace($loadAnchor,$loadNew)

$setAnchor = @'
        _autoUnmatched = autoUnmatched;
        _checked.clear();
'@
$setNew = @'
        _autoUnmatched = autoUnmatched;
        _incomplete = incomplete;
        _checked.clear();
'@
if (!$a.Contains($setAnchor)) { throw "change_approval_screen.dart: setState anchor 없음" }
$a = $a.Replace($setAnchor,$setNew)

$cardAnchor = "  Widget _autoUnmatchedCard(Map<String, dynamic> row) {"
$incompleteCode = @'
  Future<void> _reviewIncomplete(
    Map<String, dynamic> row, {
    required bool lock,
  }) async {
    final name = TextEditingController(text: '${row['consignee_name'] ?? ''}');
    final phone = TextEditingController(text: '${row['consignee_phone'] ?? ''}');
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');

    final save = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(lock ? '확인 완료 / 데이터 잠금' : '불확실 데이터 확인 / 수정'),
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
                      labelText: '전화번호 (없으면 비워도 됨)',
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
                child: Text(lock ? '확정 및 잠금' : '수정 저장'),
              ),
            ],
          ),
        ) ??
        false;

    if (save) {
      try {
        await UnknownRecipientService.instance.reviewIncomplete(
          shipmentId: '${row['id']}',
          consigneeName: name.text,
          consigneePhone: phone.text,
          notes: notes.text,
          lock: lock,
        );
        if (mounted) {
          _message(lock
              ? '불확실 데이터를 확인 완료하고 잠금했습니다.'
              : '불확실 데이터를 수정했습니다.');
          await _load();
        }
      } catch (error) {
        _message('불확실 데이터 처리 실패: $error');
      }
    }

    name.dispose();
    phone.dispose();
    notes.dispose();
  }

  Widget _incompleteCard(Map<String, dynamic> row) {
    return Card(
      color: const Color(0xFFFFFBF2),
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
            Text('수취인/회사명: ${row['consignee_name'] ?? ''}'),
            Text('전화번호: ${row['consignee_phone'] ?? '(없음)'}'),
            Text(
              '영수번호: ${row['receipt_number'] ?? '-'} · '
              '구획: ${row['unloading_zone'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                '이름은 있으나 연락처가 없어 확인이 필요한 데이터입니다.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
          ],
        ),
      ),
    );
  }

'@
if (!$a.Contains($cardAnchor)) { throw "change_approval_screen.dart: card anchor 없음" }
if (!$a.Contains("_incompleteCard")) { $a = $a.Replace($cardAnchor,$incompleteCode+$cardAnchor) }

$buildAnchor = @'
                    if (_autoUnmatched.isNotEmpty) ...[
'@
$buildSection = @'
                    if (_incomplete.isNotEmpty) ...[
                      const Text(
                        '불확실 / 확인 필요 데이터',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '이름은 확인되지만 연락처가 없는 화물입니다. 일반 영수번호/구획으로 정리되며, 확인 후 잠금하면 이 목록에서 완료 처리됩니다.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      ..._incomplete.map(_incompleteCard),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    if (_autoUnmatched.isNotEmpty) ...[
'@
if (!$a.Contains($buildAnchor)) { throw "change_approval_screen.dart: build anchor 없음" }
$a = $a.Replace($buildAnchor,$buildSection)

# empty-state 조건에 incomplete 포함
$a = $a.Replace(
"if (_requests.isEmpty && _unknownClaims.isEmpty && _autoUnmatched.isEmpty)",
"if (_requests.isEmpty && _unknownClaims.isEmpty && _autoUnmatched.isEmpty && _incomplete.isEmpty)")

# stale unknown 안내문 수정
$a = $a.Replace(
"등록 고객의 이름/회사명 + 전화번호와 매칭되지 않은 화물입니다. 원본 항차에는 그대로 남고, 임시 영수번호 XX / 구획 F로 유지됩니다.",
"수취인 이름이 없거나 명시적으로 수취인 불명으로 표시된 화물입니다. 확인 전에는 임시 영수번호 XX / 구획 F로 유지됩니다.")

Set-Content $approval $a -Encoding UTF8

# SQL 복사
Copy-Item (Join-Path $root "patch_files\supabase\072_name_only_incomplete_locked_reupload.sql") `
          (Join-Path $root "supabase\072_name_only_incomplete_locked_reupload.sql") -Force

Write-Host "[OK] 업로드 진행률 숫자 % + 단계별 진행 적용" -ForegroundColor Green
Write-Host "[OK] 이름만 있는 화물 = 일반 영수번호/Zone + 확인 필요로 분리" -ForegroundColor Green
Write-Host "[OK] 불확실 데이터 확인/수정 + 확정/잠금 UI 추가" -ForegroundColor Green
Write-Host "[OK] 잠금 화물 재업로드는 기존값 유지 + 변경 승인 요청 구조 SQL 포함" -ForegroundColor Green
Write-Host ""
Write-Host "1) 먼저 flutter analyze" -ForegroundColor Cyan
Write-Host "2) 오류 0 확인 후 Supabase SQL Editor에서 아래 파일 전체 실행:" -ForegroundColor Cyan
Write-Host "   supabase\072_name_only_incomplete_locked_reupload.sql"
Write-Host "3) flutter run" -ForegroundColor Cyan
