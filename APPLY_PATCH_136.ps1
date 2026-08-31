$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$excel = Join-Path $root "lib\services\excel_import_service.dart"
$shipment = Join-Path $root "lib\services\shipment_service.dart"

if (!(Test-Path $excel)) { throw "파일 없음: $excel" }
if (!(Test-Path $shipment)) { throw "파일 없음: $shipment" }

Copy-Item $excel "$excel.bak_before_patch136" -Force
Copy-Item $shipment "$shipment.bak_before_patch136" -Force

# ============================================================
# 1) 실제 구형/실무 Excel 호환
#    수신인 E가 비어 있고 D에 이름이 들어간 경우 자동 보정
# ============================================================
$s = Get-Content $excel -Raw -Encoding UTF8

$needle = @'
          final box = '${map['box_number'] ?? ''}'.trim();
          if (box.isEmpty) {
'@

$insert = @'
          // 실무에서 오래 사용한 일부 Excel은 현재 헤더 형식은 유지하면서
          // 실제 값은 D(발신인)에 수령인 이름을 넣고 E(수신인)는 비워 둔 경우가 있습니다.
          // 전화번호(F)가 있고 E가 비어 있으면 D의 값이 사람이름/회사명일 때만
          // 수령인으로 안전하게 보정합니다. A001 같은 내부코드/반품 표시는 제외합니다.
          final consignee = '${map['consignee_name'] ?? ''}'.trim();
          final sender = '${map['sender_name'] ?? ''}'.trim();
          final phone = '${map['consignee_phone'] ?? ''}'.trim();
          if (consignee.isEmpty &&
              phone.isNotEmpty &&
              _looksLikeLegacyConsigneeName(sender)) {
            map['consignee_name'] = sender;
          }

          // 같은 구형 실무 파일에서 G에 수량(대부분 1), I가 비어 있는 경우 보정.
          final quantityText = '${map['quantity'] ?? ''}'.trim();
          final legacyContents = '${map['contents'] ?? ''}'.trim();
          if (quantityText.isEmpty) {
            final legacyQuantity = int.tryParse(legacyContents);
            if (legacyQuantity != null && legacyQuantity >= 1) {
              map['quantity'] = legacyQuantity.toString();
              map['contents'] = '';
            }
          }

          // 구형 파일에서 P(비고)에 Excel 날짜 serial이 있고 Q(접수일)가 비어 있는 경우.
          final received = '${map['received_at'] ?? ''}'.trim();
          final legacyDate = '${map['notes'] ?? ''}'.trim();
          if (received.isEmpty) {
            final serial = int.tryParse(legacyDate);
            if (serial != null && serial >= 30000 && serial <= 70000) {
              map['received_at'] = _excelSerialDate(serial);
              map['notes'] = '';
            }
          }

          final box = '${map['box_number'] ?? ''}'.trim();
          if (box.isEmpty) {
'@

if (!$s.Contains($needle)) {
  throw "excel_import_service.dart: 화물 row 처리 위치를 찾지 못했습니다."
}
$s = $s.Replace($needle,$insert)

$helperAnchor = @'
  static bool _isCustomerNameHeader(String value) {
'@
$helpers = @'
  static bool _looksLikeLegacyConsigneeName(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;

    // 내부 분류 코드(A001 등), 숫자만, 반품/취소 같은 업무 표시값은 이름으로 보지 않습니다.
    if (RegExp(r'^[A-Z]\d{2,5}$', caseSensitive: false).hasMatch(text)) {
      return false;
    }
    if (RegExp(r'^\d+$').hasMatch(text)) return false;

    final lowered = text.toLowerCase();
    if (lowered == '반품' ||
        lowered == '취소' ||
        lowered == 'return' ||
        lowered == 'unknown' ||
        lowered == '미상' ||
        lowered.contains('수취인 불명')) {
      return false;
    }
    return true;
  }

  static String _excelSerialDate(int serial) {
    // Excel 1900 date system. 25569 == 1970-01-01.
    final millis = (serial - 25569) * Duration.millisecondsPerDay;
    final date = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

'@

if (!$s.Contains($helperAnchor)) {
  throw "excel_import_service.dart: helper 삽입 위치를 찾지 못했습니다."
}
$s = $s.Replace($helperAnchor,$helpers+$helperAnchor)
Set-Content $excel $s -Encoding UTF8
Write-Host "[OK] 실제 구형 Excel 이름/수량/접수일 자동 보정" -ForegroundColor Green

# ============================================================
# 2) 관리자/직원/파트너 검색에서 수취인 불명 화물도 반드시 보이도록 보강
#    기존 RPC 결과 + recipient_unknown=true 직접 조회를 합침
# ============================================================
$t = Get-Content $shipment -Raw -Encoding UTF8

$oldReturn = @'
    final rows = await SupabaseService.client.rpc(
      'search_shipments_for_current_user',
      params: {
        'p_route': route == '전체' ? '' : route,
        'p_year': year == '전체' ? null : parsedYear,
        'p_voyage': voyageValue,
        'p_box_number': boxNumber.trim(),
        'p_invoice': invoice.trim(),
        'p_recipient': recipient.trim(),
        'p_phone': phone.trim(),
      },
    );
    return List<Map<String, dynamic>>.from(rows as List);
'@

$newReturn = @'
    final rows = await SupabaseService.client.rpc(
      'search_shipments_for_current_user',
      params: {
        'p_route': route == '전체' ? '' : route,
        'p_year': year == '전체' ? null : parsedYear,
        'p_voyage': voyageValue,
        'p_box_number': boxNumber.trim(),
        'p_invoice': invoice.trim(),
        'p_recipient': recipient.trim(),
        'p_phone': phone.trim(),
      },
    );

    final result = List<Map<String, dynamic>>.from(rows as List);

    // 관리자·직원·협력/파트너 검색에서는 수취인 불명 화물도 일반 화물 검색 결과
    // 아래에 보여야 합니다. 과거 RPC 버전에 recipient_unknown 제외 조건이 남아 있어도
    // 앱에서 해당 항차의 불명 화물을 보강해 누락되지 않게 합니다.
    final isManager = currentUser.role == UserRole.admin ||
        currentUser.role == UserRole.staff ||
        currentUser.role == UserRole.partner;

    if (isManager) {
      try {
        var query = SupabaseService.client
            .from('shipments')
            .select()
            .eq('recipient_unknown', true);

        if (route != '전체') {
          query = query.eq('route', route);
        }
        if (parsedYear != null && year != '전체') {
          query = query.eq('shipment_year', parsedYear);
        }
        if (voyageValue.isNotEmpty) {
          query = query.eq('voyage', voyageValue);
        }

        final unknownRaw = await query;
        final unknownRows =
            List<Map<String, dynamic>>.from(unknownRaw as List);

        bool containsIgnoreCase(dynamic source, String term) {
          if (term.trim().isEmpty) return true;
          return '${source ?? ''}'
              .toLowerCase()
              .contains(term.trim().toLowerCase());
        }

        final filtered = unknownRows.where((row) {
          if (!containsIgnoreCase(row['box_number'], boxNumber)) return false;
          if (!containsIgnoreCase(row['invoice_number'], invoice)) return false;
          if (!containsIgnoreCase(row['consignee_name'], recipient)) return false;
          if (!containsIgnoreCase(row['consignee_phone'], phone)) return false;

          final deletionStatus =
              '${row['deletion_status'] ?? 'active'}'.trim().toLowerCase();
          return deletionStatus != 'pending';
        });

        final existingIds = result.map((row) => '${row['id']}').toSet();
        for (final row in filtered) {
          if (existingIds.add('${row['id']}')) {
            result.add(row);
          }
        }
      } catch (_) {
        // 불명 화물 보강 실패가 기존 검색 RPC 결과까지 막지는 않도록 합니다.
      }
    }

    return result;
'@

if (!$t.Contains($oldReturn)) {
  throw "shipment_service.dart: searchRows 원본 블록을 찾지 못했습니다."
}
$t = $t.Replace($oldReturn,$newReturn)
Set-Content $shipment $t -Encoding UTF8
Write-Host "[OK] 수취인 불명 화물도 관리자 검색 결과에 포함" -ForegroundColor Green

Write-Host ""
Write-Host "중요: 이미 V08에 잘못 올라간 기존 데이터는 재업로드해야 이름 보정이 적용됩니다." -ForegroundColor Yellow
Write-Host "같은 import_key로 upsert되므로 같은 V08 파일을 다시 올리면 됩니다." -ForegroundColor Yellow
Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
Write-Host "flutter run"
