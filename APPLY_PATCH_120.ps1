$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) { return Get-Content -Raw -Encoding UTF8 $Path }
function Write-Utf8([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}
function Replace-Required([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  if (!$Text.Contains($Old)) { throw "Patch120 중단: '$Label' 기준 코드를 찾지 못했습니다." }
  return $Text.Replace($Old, $New)
}
function Install-TextFile([string]$RelativeSource, [string]$RelativeTarget) {
  $src = Join-Path $PSScriptRoot $RelativeSource
  $dst = Join-Path (Get-Location).Path $RelativeTarget
  $dir = Split-Path $dst
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $content = Read-Utf8 $src
  Write-Utf8 $dst $content
}

$project = (Get-Location).Path

# New service/screens + full central FreightService replacement.
Install-TextFile "patch_files\lib\services\customer_benefit_service.dart.txt" "lib\services\customer_benefit_service.dart"
Install-TextFile "patch_files\lib\services\freight_service.dart.txt" "lib\services\freight_service.dart"
Install-TextFile "patch_files\lib\screens\discount_management_screen.dart.txt" "lib\screens\discount_management_screen.dart"
Install-TextFile "patch_files\lib\screens\local_delivery_management_screen.dart.txt" "lib\screens\local_delivery_management_screen.dart"
Install-TextFile "patch_files\lib\screens\voyage_total_management_screen.dart.txt" "lib\screens\voyage_total_management_screen.dart"
Install-TextFile "patch_files\supabase\065_discount_delivery_voyage_management.sql.txt" "supabase\065_discount_delivery_voyage_management.sql"
Write-Host "설치 완료: 할인/배송/항차총액 서비스 및 화면 + SQL"

# ---------------------------------------------------------------------------
# Management menu: ADMIN-only 3 buttons.
# ---------------------------------------------------------------------------
$menu = Join-Path $project "lib\screens\management_menu_screen.dart"
Copy-Item $menu "$menu.bak_before_patch120" -Force
$src = Read-Utf8 $menu
$src = $src.Replace("`r`n", "`n")
if (!$src.Contains("discount_management_screen.dart")) {
  $src = Replace-Required $src `
    "import 'schedule_management_screen.dart';" `
    "import 'schedule_management_screen.dart';`nimport 'discount_management_screen.dart';`nimport 'local_delivery_management_screen.dart';`nimport 'voyage_total_management_screen.dart';" `
    "관리메뉴 import"
}
if (!$src.Contains("'label': '할인 적용 관리'")) {
$old = @'
        {
          'label': '엑셀 데이타 일괄 관리\n(편집 잠금/해제, 구획 및 영수 번호 관리)',
          'icon': Icons.table_view_outlined,
          'page': const ExcelBulkManagementScreen(),
        },
'@
$new = @'
        {
          'label': '엑셀 데이타 일괄 관리\n(편집 잠금/해제, 구획 및 영수 번호 관리)',
          'icon': Icons.table_view_outlined,
          'page': const ExcelBulkManagementScreen(),
        },
        {
          'label': '할인 적용 관리',
          'icon': Icons.percent_outlined,
          'page': const DiscountManagementScreen(),
        },
        {
          'label': '시내.지방 배송 관리',
          'icon': Icons.local_shipping_outlined,
          'page': const LocalDeliveryManagementScreen(),
        },
        {
          'label': '항차별 총액 관리',
          'icon': Icons.analytics_outlined,
          'page': const VoyageTotalManagementScreen(),
        },
'@
  $src = Replace-Required $src $old $new "관리메뉴 버튼 3개"
}
Write-Utf8 $menu $src
Write-Host "수정 완료: 총괄 관리자 관리메뉴 3개 추가"

# ---------------------------------------------------------------------------
# Excel import mapping: future/new files may use 특이사항 instead of 발신인.
# Existing 발신인 remains accepted for backward compatibility.
# ---------------------------------------------------------------------------
$excel = Join-Path $project "lib\services\excel_import_service.dart"
Copy-Item $excel "$excel.bak_before_patch120" -Force
$src = Read-Utf8 $excel
$src = $src.Replace("`r`n", "`n")
if (!$src.Contains("'특이사항': 'sender_name'")) {
  $src = Replace-Required $src `
    "      '발신인': 'sender_name'," `
    "      '발신인': 'sender_name',`n      '특이사항': 'sender_name'," `
    "엑셀 특이사항 alias"
}
Write-Utf8 $excel $src
Write-Host "수정 완료: 발신인/특이사항 양쪽 Excel header 호환"

# ---------------------------------------------------------------------------
# Excel bulk service/editor: sender_name is now shown as 특이사항.
# Auto-matched benefit note remains separate/read-only.
# ---------------------------------------------------------------------------
$bulkService = Join-Path $project "lib\services\excel_bulk_management_service.dart"
Copy-Item $bulkService "$bulkService.bak_before_patch120" -Force
$src = Read-Utf8 $bulkService
$src = $src.Replace("`r`n", "`n")
if (!$src.Contains("required String senderName")) {
  $src = Replace-Required $src `
    "    required String boxNumber,`n    required String name," `
    "    required String boxNumber,`n    required String senderName,`n    required String name," `
    "Excel bulk senderName parameter"
  $src = Replace-Required $src `
    "        'p_box_number': boxNumber.trim(),`n        'p_consignee_name': name.trim()," `
    "        'p_box_number': boxNumber.trim(),`n        'p_sender_name': senderName.trim(),`n        'p_consignee_name': name.trim()," `
    "Excel bulk senderName RPC"
}
Write-Utf8 $bulkService $src

$bulkScreen = Join-Path $project "lib\screens\excel_bulk_management_screen.dart"
Copy-Item $bulkScreen "$bulkScreen.bak_before_patch120" -Force
$src = Read-Utf8 $bulkScreen
$src = $src.Replace("`r`n", "`n")
if (!$src.Contains("final special = TextEditingController")) {
  $src = Replace-Required $src `
    "    final box = TextEditingController(text: '`${row['box_number'] ?? ''}');`n    final name = TextEditingController" `
    "    final box = TextEditingController(text: '`${row['box_number'] ?? ''}');`n    final special = TextEditingController(text: '`${row['sender_name'] ?? ''}');`n    final name = TextEditingController" `
    "Excel bulk 특이사항 controller"
  $src = Replace-Required $src `
    "                  _readOnly('`${row['invoice_number'] ?? ''}', '송장번호 (수정 불가)'),`n                  _field(name, '이름')," `
    "                  _readOnly('`${row['invoice_number'] ?? ''}', '송장번호 (수정 불가)'),`n                  _field(special, '특이사항', maxLines: 2),`n                  if ('`${row['special_note_auto'] ?? ''}'.trim().isNotEmpty)`n                    _readOnly('`${row['special_note_auto'] ?? ''}', '자동 매칭 특이사항'),`n                  _field(name, '이름')," `
    "Excel bulk 특이사항 field"
  $src = Replace-Required $src `
    "          boxNumber: box.text,`n          name: name.text," `
    "          boxNumber: box.text,`n          senderName: special.text,`n          name: name.text," `
    "Excel bulk 특이사항 save"
  $src = Replace-Required $src `
    "    box.dispose();`n    name.dispose();" `
    "    box.dispose();`n    special.dispose();`n    name.dispose();" `
    "Excel bulk 특이사항 dispose"
}
Write-Utf8 $bulkScreen $src
Write-Host "수정 완료: Excel 일괄관리 발신인 -> 특이사항 편집/자동 매칭 표시"

# ---------------------------------------------------------------------------
# Statement: matched local delivery body + actual discount amount.
# ---------------------------------------------------------------------------
$statement = Join-Path $project "lib\screens\statement_preview_dialog.dart"
Copy-Item $statement "$statement.bak_before_patch120" -Force
$src = Read-Utf8 $statement
$src = $src.Replace("`r`n", "`n")
if (!$src.Contains("customer_benefit_service.dart")) {
  $src = Replace-Required $src `
    "import '../services/statement_service.dart';" `
    "import '../services/statement_service.dart';`nimport '../services/customer_benefit_service.dart';" `
    "명세서 CustomerBenefitService import"
}
if (!$src.Contains("String _inlandDeliveryText = '';")) {
  $src = Replace-Required $src `
    "  String? _arrivalDate;" `
    "  String? _arrivalDate;`n  String _inlandDeliveryText = '';" `
    "명세서 inland state"
}
if (!$src.Contains("CustomerBenefitService.instance.inlandTextForRows(widget.routeLabel, rows)")) {
$old = @'
      final arrival = await StatementService.instance.arrivalDate(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
      );
'@
$new = @'
      final arrival = await StatementService.instance.arrivalDate(
        route: widget.routeLabel,
        year: widget.year,
        voyage: widget.voyage,
      );
      final inland = await CustomerBenefitService.instance
          .inlandTextForRows(widget.routeLabel, rows);
'@
  $src = Replace-Required $src $old $new "명세서 inland 조회"
  $src = Replace-Required $src `
    "        _arrivalDate = arrival;" `
    "        _arrivalDate = arrival;`n        _inlandDeliveryText = inland;" `
    "명세서 inland state 저장"
}
if (!$src.Contains("inlandDeliveryText: _inlandDeliveryText")) {
  $src = Replace-Required $src `
    "        arrivalDate: _arrivalDate," `
    "        arrivalDate: _arrivalDate,`n        inlandDeliveryText: _inlandDeliveryText," `
    "명세서 painter inland 전달"
}
if (!$src.Contains("required this.inlandDeliveryText")) {
  $src = Replace-Required $src `
    "    required this.arrivalDate," `
    "    required this.arrivalDate,`n    required this.inlandDeliveryText," `
    "painter constructor inland"
  $src = Replace-Required $src `
    "  final String? arrivalDate;" `
    "  final String? arrivalDate;`n  final String inlandDeliveryText;" `
    "painter field inland"
}
# Draw body under Inland heading.
if (!$src.Contains("inlandDeliveryText,`n        Rect.fromLTWH(leftW * .58 + 14")) {
$old = @'
    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);
    
'@
$new = @'
    _text(c, 'Inland delivery/시내·지방 배송',
        Rect.fromLTWH(leftW * .58 + 14, sumTop + 7, leftW * .42 - 24, 24),
        18, bold: true);
    _text(
      c,
      inlandDeliveryText,
      Rect.fromLTWH(leftW * .58 + 14, sumTop + 38, leftW * .42 - 24, 112),
      15.5,
      maxLines: 5,
      lineHeight: 1.12,
    );
    
'@
  $src = Replace-Required $src $old $new "명세서 Inland body"
}
# Actual discount amount in totals box.
$src = Replace-Required $src `
  "    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .44, adjH), 16, bold: true, right: true);" `
  "    _text(c, freight.discountTotalUsd > 0 ? '-`${MoneyFormat.usd(freight.discountTotalUsd)}' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .44, adjH), 16, bold: true, right: true);" `
  "명세서 할인 금액"

# Batch statement renderer: same inland lookup + painter arg.
if (!$src.Contains("inlandTextForRows(request.routeLabel, rows)")) {
$old = @'
    final arrival = await StatementService.instance.arrivalDate(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
    );
'@
$new = @'
    final arrival = await StatementService.instance.arrivalDate(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
    );
    final inland = await CustomerBenefitService.instance
        .inlandTextForRows(request.routeLabel, rows);
'@
  $src = Replace-Required $src $old $new "배치 명세서 inland 조회"
  $oldPainter = @'
      arrivalDate: arrival,
      logo: assets[0],
'@
  $newPainter = @'
      arrivalDate: arrival,
      inlandDeliveryText: inland,
      logo: assets[0],
'@
  $src = Replace-Required $src $oldPainter $newPainter "배치 명세서 inland 전달"
}
Write-Utf8 $statement $src
Write-Host "수정 완료: 명세서 실제 할인 금액 + Inland delivery 자동 기입"

Write-Host ""
Write-Host "Patch120 적용 완료"
Write-Host "- 총괄: 할인 적용 관리"
Write-Host "- 총괄: 시내.지방 배송 관리"
Write-Host "- 총괄: 항차별 총액 관리"
Write-Host "- 할인은 중앙 FreightService에 적용 (운임확인/명세서 공통)"
Write-Host "- Excel 발신인과 특이사항 둘 다 import 가능"
Write-Host "- 자동 특이사항은 기존 sender_name 수기값을 덮지 않고 special_note_auto에 별도 보관"
Write-Host "- SQL 있음: supabase/065_discount_delivery_voyage_management.sql"
