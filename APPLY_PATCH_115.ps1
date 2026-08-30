$ErrorActionPreference = "Stop"

function Replace-Exact {
  param(
    [string]$Path,
    [string]$Old,
    [string]$New,
    [string]$Label
  )
  $src = Get-Content -Raw -Encoding UTF8 $Path
  if (!$src.Contains($Old)) {
    throw "$Label : 대상 코드를 찾지 못했습니다. 로컬 파일이 현재 master와 다른지 확인하세요. ($Path)"
  }
  $src = $src.Replace($Old, $New)
  Set-Content -Path $Path -Value $src -Encoding UTF8
  Write-Host "수정 완료: $Label"
}

$project = (Get-Location).Path

# ---------------------------------------------------------------------------
# 1) 가견적서: 도장 전체 이미지 최대 확대 + 한국계좌 줄간격
# ---------------------------------------------------------------------------
$q = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
if (!(Test-Path $q)) { throw "파일 없음: $q" }
Copy-Item $q "$q.bak_before_patch115" -Force

Replace-Exact $q `
"_imageContainTrimmed(c, stamp, Rect.fromLTWH(8, signTop + 27, signW - 16, signH - 29), trimRatio: .18);" `
"_imageContain(c, stamp, Rect.fromLTWH(8, signTop + 4, signW - 16, signH - 8));" `
"가견적서 도장 전체 최대 확대"

$src = Get-Content -Raw -Encoding UTF8 $q
$oldTextSig = "void _text(Canvas c, String text, Rect r, double size,`n      {bool bold = false, bool center = false, bool right = false, int maxLines = 3})"
$newTextSig = "void _text(Canvas c, String text, Rect r, double size,`n      {bool bold = false, bool center = false, bool right = false, int maxLines = 3, double lineHeight = 1.15})"
if (!$src.Contains($oldTextSig)) { throw "가견적서 _text 시그니처를 찾지 못했습니다." }
$src = $src.Replace($oldTextSig, $newTextSig)
$src = $src.Replace("height: 1.15,", "height: lineHeight,")

$oldAccount = @"
      '한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호',
      payRects[3].deflate(8),
      22,
      bold: true,
      center: true,
      maxLines: 4,
"@
$newAccount = @"
      '한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호',
      payRects[3].deflate(8),
      22,
      bold: true,
      center: true,
      maxLines: 4,
      lineHeight: 1.35,
"@
if (!$src.Contains($oldAccount)) { throw "가견적서 한국계좌 출력부를 찾지 못했습니다." }
$src = $src.Replace($oldAccount, $newAccount)
Set-Content -Path $q -Value $src -Encoding UTF8

# ---------------------------------------------------------------------------
# 2) 명세서: Zone 실제 DB 필드 표시 + 도장 전체 최대 확대 + 한국계좌 줄간격
# ---------------------------------------------------------------------------
$s = Join-Path $project "lib\screens\statement_preview_dialog.dart"
if (!(Test-Path $s)) { throw "파일 없음: $s" }
Copy-Item $s "$s.bak_before_patch115" -Force

Replace-Exact $s `
"_labelValue(c, '구획(Zone)', _s(rows.first['zone'])," `
"_labelValue(c, '구획(Zone)', _s(rows.first['unloading_zone'])," `
"명세서 상단 Zone 실제 필드 연결"

Replace-Exact $s `
"_imageContainTrimmed(c, stamp, Rect.fromLTWH(8, signTop + 27, signW - 16, signH - 29), trimRatio: .18);" `
"_imageContain(c, stamp, Rect.fromLTWH(8, signTop + 4, signW - 16, signH - 8));" `
"명세서 도장 전체 최대 확대"

$src = Get-Content -Raw -Encoding UTF8 $s
if (!$src.Contains($oldTextSig)) { throw "명세서 _text 시그니처를 찾지 못했습니다." }
$src = $src.Replace($oldTextSig, $newTextSig)
$src = $src.Replace("height: 1.15,", "height: lineHeight,")
if (!$src.Contains($oldAccount)) { throw "명세서 한국계좌 출력부를 찾지 못했습니다." }
$src = $src.Replace($oldAccount, $newAccount)
Set-Content -Path $s -Value $src -Encoding UTF8

# ---------------------------------------------------------------------------
# 3) 화물 조회 카드 정보 구성
#    기존 권한은 유지: Zone은 기존 _showZone 조건 그대로
# ---------------------------------------------------------------------------
$search = Join-Path $project "lib\screens\shipment_search_screen.dart"
if (!(Test-Path $search)) { throw "파일 없음: $search" }
Copy-Item $search "$search.bak_before_patch115" -Force

$src = Get-Content -Raw -Encoding UTF8 $search
$start = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> r) {")
$end = $src.IndexOf("  String _voyageLabel(dynamic value) {", $start)
if ($start -lt 0 -or $end -lt 0) { throw "화물 조회 카드 함수 범위를 찾지 못했습니다." }

$newSearchCard = @'
  Widget _shipmentCard(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final quantity = int.tryParse('${r['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(r['received_at']);
    final length = '${r['length_cm'] ?? ''}'.trim();
    final height = '${r['height_cm'] ?? ''}'.trim();
    final width = '${r['width_cm'] ?? ''}'.trim();
    final size = '$length × $height × $width cm';
    final name = '${r['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(r);
    final nameCompany = '$name / ${company.isEmpty ? '-' : company}';
    final receipt = '${r['receipt_number'] ?? ''}'.trim();
    final zone = '${r['unloading_zone'] ?? ''}'.trim();

    return Card(
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selectedIds.contains(id),
                onChanged: (_) => _toggle(id),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '박스번호: ${r['box_number'] ?? ''} / 박스개수: ${quantity}개 / 입고 날짜: $receivedDate',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _row('운송 경로', '${r['route'] ?? ''}'),
                    _row(
                      '년도 / 항차',
                      '${r['shipment_year'] ?? ''} / ${_voyageLabel(r['voyage'])}',
                    ),
                    _row('송장번호', '${r['invoice_number'] ?? ''}'),
                    _row('이름/수령인 & 회사', nameCompany),
                    _row('연락처', '${r['consignee_phone'] ?? ''}'),
                    _row(
                      '무게/크기(L H W)',
                      '${r['weight_kg'] ?? ''} kg / $size',
                    ),
                    if (_showZone)
                      _row(
                        '영수증 번호 & 구획 (Zone)',
                        '$receipt & ${zone.isEmpty ? '-' : zone}',
                      )
                    else
                      _row('영수증 번호', receipt),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.length >= 10 ? text.substring(0, 10) : text;
    }
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _companyOf(Map<String, dynamic> row) {
    for (final key in const ['consignee_company', 'company_name', 'company']) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

'@
$src = $src.Substring(0, $start) + $newSearchCard + $src.Substring($end)
Set-Content -Path $search -Value $src -Encoding UTF8
Write-Host "수정 완료: 화물 조회 카드 표시 항목"

# ---------------------------------------------------------------------------
# 4) 화물 관리 카드 정보 구성 + 각 카드 오른쪽 편집 버튼
#    기존 관리자/직원 Zone 표시 권한은 유지
# ---------------------------------------------------------------------------
$manage = Join-Path $project "lib\screens\cargo_management_screen.dart"
if (!(Test-Path $manage)) { throw "파일 없음: $manage" }
Copy-Item $manage "$manage.bak_before_patch115" -Force

$src = Get-Content -Raw -Encoding UTF8 $manage
$start = $src.IndexOf("  Widget _groupShipmentCard(Map<String, dynamic> item) {")
$end = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> item) {", $start)
if ($start -lt 0 -or $end -lt 0) { throw "화물 관리 그룹 카드 함수 범위를 찾지 못했습니다." }

$newGroupCard = @'
  Widget _groupShipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(item['received_at']);
    final length = '${item['length_cm'] ?? ''}'.trim();
    final height = '${item['height_cm'] ?? ''}'.trim();
    final width = '${item['width_cm'] ?? ''}'.trim();
    final size = '$length × $height × $width cm';
    final name = '${item['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(item);
    final nameCompany = '$name / ${company.isEmpty ? '-' : company}';
    final receipt = '${item['receipt_number'] ?? ''}'.trim();
    final zone = '${item['unloading_zone'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: _selectedIds.contains(id)
            ? Border.all(color: AppColors.accent, width: 1.5)
            : null,
      ),
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selectedIds.contains(id),
                onChanged: (_) => _toggle(id),
              ),
              Expanded(
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
                        if (_isManager)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _selectedIds.add(id));
                                    await _editCheckedGroup([item]);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('편집'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _infoRow('운송 경로', '${item['route'] ?? ''}'),
                    _infoRow(
                      '년도 / 항차',
                      '${item['shipment_year'] ?? ''} / ${_voyageLabel(item['voyage'])}',
                    ),
                    _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                    _infoRow('이름/수령인 & 회사', nameCompany),
                    _infoRow('연락처', '${item['consignee_phone'] ?? ''}'),
                    _infoRow(
                      '무게/크기(L H W)',
                      '${item['weight_kg'] ?? ''} kg / $size',
                    ),
                    if (_isAdmin || _isStaff)
                      _infoRow(
                        '영수증 번호 & 구획 (Zone)',
                        '$receipt & ${zone.isEmpty ? '-' : zone}',
                      )
                    else
                      _infoRow('영수증 번호', receipt),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

'@
$src = $src.Substring(0, $start) + $newGroupCard + $src.Substring($end)

# Replace legacy single-card function as well, so both management rendering paths stay consistent.
$start2 = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> item) {")
$end2 = $src.IndexOf("  String _voyageLabel(dynamic value) {", $start2)
if ($start2 -lt 0 -or $end2 -lt 0) { throw "화물 관리 단일 카드 함수 범위를 찾지 못했습니다." }

$newLegacyCard = @'
  Widget _shipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(item['received_at']);
    final length = '${item['length_cm'] ?? ''}'.trim();
    final height = '${item['height_cm'] ?? ''}'.trim();
    final width = '${item['width_cm'] ?? ''}'.trim();
    final size = '$length × $height × $width cm';
    final name = '${item['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(item);
    final nameCompany = '$name / ${company.isEmpty ? '-' : company}';
    final receipt = '${item['receipt_number'] ?? ''}'.trim();
    final zone = '${item['unloading_zone'] ?? ''}'.trim();

    return Card(
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selectedIds.contains(id),
                onChanged: (_) => _toggle(id),
              ),
              Expanded(
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
                        if (_isManager)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _selectedIds.add(id));
                                    await _editCheckedGroup([item]);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('편집'),
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
                    _infoRow('이름/수령인 & 회사', nameCompany),
                    _infoRow('연락처', '${item['consignee_phone'] ?? ''}'),
                    _infoRow(
                      '무게/크기(L H W)',
                      '${item['weight_kg'] ?? ''} kg / $size',
                    ),
                    if (_isAdmin || _isStaff)
                      _infoRow(
                        '영수증 번호 & 구획 (Zone)',
                        '$receipt & ${zone.isEmpty ? '-' : zone}',
                      )
                    else
                      _infoRow('영수증 번호', receipt),
                    if (_isManager) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _busy ? null : () => _requestDeletion(item),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('삭제'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.length >= 10 ? text.substring(0, 10) : text;
    }
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _companyOf(Map<String, dynamic> row) {
    for (final key in const ['consignee_company', 'company_name', 'company']) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

'@
$src = $src.Substring(0, $start2) + $newLegacyCard + $src.Substring($end2)
Set-Content -Path $manage -Value $src -Encoding UTF8
Write-Host "수정 완료: 화물 관리 카드 표시 항목 + 카드별 편집 버튼"

# ---------------------------------------------------------------------------
# 5) 사용자가 이번 메시지에 준 도장 원본으로 asset 교체
# ---------------------------------------------------------------------------
$stampSource = Join-Path $PSScriptRoot "assets\images\company_stamp.png"
$stampTarget = Join-Path $project "assets\images\company_stamp.png"
if (!(Test-Path $stampSource)) { throw "ZIP 내 도장 원본을 찾지 못했습니다: $stampSource" }
Copy-Item $stampSource $stampTarget -Force
Write-Host "수정 완료: company_stamp.png 전체 원본 교체"

Write-Host ""
Write-Host "Patch115 적용 완료"
Write-Host "- 도장 전체 이미지를 서명칸 높이에 거의 맞게 확대"
Write-Host "- 명세서 상단 Zone: shipments.unloading_zone 실제 값 연결"
Write-Host "- 한국 원화계좌 22pt 유지 + 줄간격 확대"
Write-Host "- 화물 조회/관리 카드 요청 항목 구성"
Write-Host "- 화물 관리 카드별 편집 버튼 추가"
Write-Host "- 기존 Zone 열람 권한은 그대로 유지"
Write-Host "- Remark/하단 문구는 실제 Excel 직접 확인 전 임의 변경하지 않음"
