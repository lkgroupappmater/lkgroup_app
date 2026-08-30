$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
  Get-Content -Raw -Encoding UTF8 $Path
}
function Write-Utf8([string]$Path, [string]$Text) {
  Set-Content -Path $Path -Value $Text -Encoding UTF8
}

$project = (Get-Location).Path

# ---------------------------------------------------------------------------
# 화물 조회 카드: 모든 회원이 같은 카드 구조를 사용하되 기존 권한 노출 조건 유지
# ---------------------------------------------------------------------------
$search = Join-Path $project "lib\screens\shipment_search_screen.dart"
if (!(Test-Path $search)) { throw "파일 없음: $search" }
Copy-Item $search "$search.bak_before_patch115c" -Force

$src = Read-Utf8 $search
$start = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> r) {")
$end = $src.IndexOf("  String _voyageLabel(dynamic value) {", $start)
if ($start -lt 0 -or $end -lt 0) {
  throw "화물 조회 카드 함수 범위를 찾지 못했습니다."
}

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
Write-Utf8 $search $src
Write-Host "수정 완료: 화물 조회 카드 공통 구조"

# ---------------------------------------------------------------------------
# 화물 관리 카드: 조회 카드와 동일 구조 + 기존 관리자/직원 권한에서 편집 버튼
# ---------------------------------------------------------------------------
$manage = Join-Path $project "lib\screens\cargo_management_screen.dart"
if (!(Test-Path $manage)) { throw "파일 없음: $manage" }
Copy-Item $manage "$manage.bak_before_patch115c" -Force

$src = Read-Utf8 $manage
$start = $src.IndexOf("  Widget _groupShipmentCard(Map<String, dynamic> item) {")
$end = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> item) {", $start)
if ($start -lt 0 -or $end -lt 0) {
  throw "화물 관리 그룹 카드 함수 범위를 찾지 못했습니다."
}

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
                                    setState(() {
                                      _selectedIds
                                        ..clear()
                                        ..add(id);
                                    });
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

$start2 = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> item) {")
$end2 = $src.IndexOf("  String _voyageLabel(dynamic value) {", $start2)
if ($start2 -lt 0 -or $end2 -lt 0) {
  throw "화물 관리 카드 함수 범위를 찾지 못했습니다."
}

$newCard = @'
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
                                    setState(() {
                                      _selectedIds
                                        ..clear()
                                        ..add(id);
                                    });
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
$src = $src.Substring(0, $start2) + $newCard + $src.Substring($end2)
Write-Utf8 $manage $src
Write-Host "수정 완료: 화물 관리 카드 공통 구조 + 권한별 편집 버튼"

Write-Host ""
Write-Host "Patch115c 적용 완료"
Write-Host "- SQL 실행 없음"
Write-Host "- 카드 표시 구조만 변경"
Write-Host "- 기존 권한/검색/운임/삭제/명세서 기능 변경 없음"
