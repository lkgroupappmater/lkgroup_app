$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch130: 박스번호 고정 + 영수번호 복구 ===" -ForegroundColor Cyan
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$cargoPath = Join-Path $projectRoot "lib\screens\cargo_management_screen.dart"
$manualPath = Join-Path $projectRoot "lib\screens\shipment_manual_add_screen.dart"
$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"

foreach ($p in @($cargoPath,$manualPath,$tsPath)) {
  if (!(Test-Path $p)) { throw "파일 없음: $p" }
  Copy-Item $p "$p.bak_before_patch130" -Force
}

# ----------------------------------------------------------------------
# 1) 검색한 박스번호 -> 화물 추가 화면으로 그대로 전달
# ----------------------------------------------------------------------
$cargo = Get-Content $cargoPath -Raw -Encoding UTF8

$oldCall = @'
          await _openManualAdd(
            route: _route,
            year: _year,
            voyage: _voyage,
            invoice: _invoiceController.text.trim(),
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
'@
$newCall = @'
          await _openManualAdd(
            route: _route,
            year: _year,
            voyage: _voyage,
            boxNumber: _boxNumberController.text.trim(),
            invoice: _invoiceController.text.trim(),
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
'@
if (-not $cargo.Contains($oldCall)) { throw "cargo_management_screen.dart: 검색 후 추가 호출 위치를 찾지 못했습니다." }
$cargo = $cargo.Replace($oldCall,$newCall)

$oldSig = @'
  Future<void> _openManualAdd({
    String? route,
    String? year,
    String? voyage,
    String invoice = '',
    String name = '',
    String phone = '',
  }) async {
'@
$newSig = @'
  Future<void> _openManualAdd({
    String? route,
    String? year,
    String? voyage,
    String boxNumber = '',
    String invoice = '',
    String name = '',
    String phone = '',
  }) async {
'@
if (-not $cargo.Contains($oldSig)) { throw "cargo_management_screen.dart: _openManualAdd signature 위치를 찾지 못했습니다." }
$cargo = $cargo.Replace($oldSig,$newSig)

$oldArgs = @'
          initialVoyage: selectedVoyage,
          initialInvoice: invoice,
'@
$newArgs = @'
          initialVoyage: selectedVoyage,
          initialBoxNumber: boxNumber,
          initialInvoice: invoice,
'@
if (-not $cargo.Contains($oldArgs)) { throw "cargo_management_screen.dart: manual add args 위치를 찾지 못했습니다." }
$cargo = $cargo.Replace($oldArgs,$newArgs)
Set-Content $cargoPath $cargo -Encoding UTF8

# ----------------------------------------------------------------------
# 2) Manual Add: 검색 박스번호가 있으면 "다음 번호"로 덮어쓰지 않기
# ----------------------------------------------------------------------
$manual = Get-Content $manualPath -Raw -Encoding UTF8

$oldCtor = @'
    this.initialVoyage,
    this.initialInvoice = '',
'@
$newCtor = @'
    this.initialVoyage,
    this.initialBoxNumber = '',
    this.initialInvoice = '',
'@
if (-not $manual.Contains($oldCtor)) { throw "shipment_manual_add_screen.dart: constructor 위치를 찾지 못했습니다." }
$manual = $manual.Replace($oldCtor,$newCtor)

$oldField = @'
  final String? initialVoyage;
  final String initialInvoice;
'@
$newField = @'
  final String? initialVoyage;
  final String initialBoxNumber;
  final String initialInvoice;
'@
if (-not $manual.Contains($oldField)) { throw "shipment_manual_add_screen.dart: field 위치를 찾지 못했습니다." }
$manual = $manual.Replace($oldField,$newField)

$oldInit = @'
    _voyage = widget.initialVoyage;
    _invoice.text = widget.initialInvoice;
    _name.text = widget.initialName;
    _phone.text = widget.initialPhone;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeReady) _loadNextBoxNumber();
    });
'@
$newInit = @'
    _voyage = widget.initialVoyage;
    _box.text = widget.initialBoxNumber;
    _invoice.text = widget.initialInvoice;
    _name.text = widget.initialName;
    _phone.text = widget.initialPhone;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_routeReady) return;
      if (_box.text.trim().isNotEmpty) {
        _checkDuplicates();
      } else {
        _loadNextBoxNumber();
      }
    });
'@
if (-not $manual.Contains($oldInit)) { throw "shipment_manual_add_screen.dart: initState 위치를 찾지 못했습니다." }
$manual = $manual.Replace($oldInit,$newInit)
Set-Content $manualPath $manual -Encoding UTF8

# ----------------------------------------------------------------------
# 3) Excel: 고정 박스번호 슬롯 보존
#    기존엔 DB shipment를 연속 행에 밀어넣어 S002/S005 같은 미사용 번호가 사라졌음.
#    이제 템플릿 B열 박스번호를 기준으로 같은 번호의 데이터만 해당 행에 기입.
# ----------------------------------------------------------------------
$ts = Get-Content $tsPath -Raw -Encoding UTF8

$oldLoop = @'
  let output = sheetXml;
  for (let i = 0; i < shipments.length; i++) {
    const candidate = candidateRows[i];
    const shipment = shipments[i];
    let rowXml = candidate.xml;

    for (const [column, key, kind] of mapping) {
      rowXml = updateCellPreservingFormula(
        rowXml,
        candidate.number,
        column,
        shipment[key],
        kind,
      );
    }

    output = output.replace(candidate.xml, rowXml);
  }
  return output;
'@
$newLoop = @'
  // 박스번호는 현장 입고 순서 기준으로 템플릿에 고정된 슬롯입니다.
  // DB 데이터가 없는 번호도 "아직 사용하지 않은 번호"로 남겨야 하므로
  // shipments를 위에서부터 압축해 쓰지 않고 B열의 고정 박스번호와 정확히 매칭합니다.
  const shipmentByBox = new Map<string, Record<string, unknown>>();
  for (const shipment of shipments) {
    const box = String(shipment.box_number ?? '').trim().toUpperCase();
    if (box) shipmentByBox.set(box, shipment);
  }

  let output = sheetXml;
  const matchedBoxes = new Set<string>();

  for (const candidate of candidateRows) {
    const bRe = new RegExp(
      `<c\\b[^>]*r="B${candidate.number}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`,
    );
    const bMatch = candidate.xml.match(bRe);
    if (!bMatch) continue;

    const fixedBox = cellText(bMatch[0], strings).trim();
    if (!fixedBox) continue;

    const shipment = shipmentByBox.get(fixedBox.toUpperCase());
    if (!shipment) continue;

    matchedBoxes.add(fixedBox.toUpperCase());
    let rowXml = candidate.xml;

    // B열은 템플릿 고정 번호이므로 절대 덮어쓰지 않습니다.
    for (const [column, key, kind] of mapping) {
      if (column === 'B') continue;
      rowXml = updateCellPreservingFormula(
        rowXml,
        candidate.number,
        column,
        shipment[key],
        kind,
      );
    }

    output = output.replace(candidate.xml, rowXml);
  }

  const missing = [...shipmentByBox.keys()].filter((box) => !matchedBoxes.has(box));
  if (missing.length > 0) {
    throw new Error(
      `Excel 템플릿에 없는 박스번호가 있습니다: ${missing.slice(0, 10).join(', ')}`,
    );
  }

  return output;
'@
if (-not $ts.Contains($oldLoop)) { throw "index.ts: updateCargoSheet loop 위치를 찾지 못했습니다." }
$ts = $ts.Replace($oldLoop,$newLoop)

# ----------------------------------------------------------------------
# 4) LKS XX 복구:
#    이름+연락처가 있는 정상 고객인데 기존 receipt가 XX면 "미배정"으로 보고 정상 번호 재부여.
# ----------------------------------------------------------------------
$oldExisting1 = @'
    const existing = String(shipment.receipt_number ?? '').trim();
    if (existing) {
      const m = existing.match(/(\d+)\s*$/);
'@
$newExisting1 = @'
    const existing = String(shipment.receipt_number ?? '').trim();
    const hasIdentity =
      String(shipment.consignee_name ?? '').trim() !== '' &&
      normalizePhone(shipment.consignee_phone) !== '';
    const recoverableXx = hasIdentity && /\bXX\s*$/i.test(existing);
    if (existing && !recoverableXx) {
      const m = existing.match(/(\d+)\s*$/);
'@
if (-not $ts.Contains($oldExisting1)) { throw "index.ts: assignReceiptNumbers 1차 existing 위치를 찾지 못했습니다." }
$ts = $ts.Replace($oldExisting1,$newExisting1)

$oldExisting2 = @'
    const existing = String(shipment.receipt_number ?? '').trim();
    if (existing) return shipment;

    const name = String(shipment.consignee_name ?? '').trim();
    const phone = normalizePhone(shipment.consignee_phone);
'@
$newExisting2 = @'
    const existing = String(shipment.receipt_number ?? '').trim();
    const name = String(shipment.consignee_name ?? '').trim();
    const phone = normalizePhone(shipment.consignee_phone);
    const recoverableXx = name !== '' && phone !== '' && /\bXX\s*$/i.test(existing);
    if (existing && !recoverableXx) return shipment;

'@
if (-not $ts.Contains($oldExisting2)) { throw "index.ts: assignReceiptNumbers 2차 existing 위치를 찾지 못했습니다." }
$ts = $ts.Replace($oldExisting2,$newExisting2)

$oldDb = @'
      if (id && receipt && !originalReceipt) {
'@
$newDb = @'
      const originalWasRecoverableXx =
        /\bXX\s*$/i.test(originalReceipt) &&
        String(shipment.consignee_name ?? '').trim() !== '' &&
        normalizePhone(shipment.consignee_phone) !== '' &&
        !/\bXX\s*$/i.test(receipt);
      if (id && receipt && (!originalReceipt || originalWasRecoverableXx)) {
'@
if (-not $ts.Contains($oldDb)) { throw "index.ts: receipt DB update 조건 위치를 찾지 못했습니다." }
$ts = $ts.Replace($oldDb,$newDb)

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] 검색한 박스번호를 화물 추가화면에 그대로 전달" -ForegroundColor Green
Write-Host "[OK] Excel 고정 박스번호/빈 슬롯 보존" -ForegroundColor Green
Write-Host "[OK] 이름+연락처가 있는 LKS XX 정상 번호 자동 복구" -ForegroundColor Green
Write-Host ""
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  flutter analyze"
Write-Host "  npx supabase functions deploy export-shipment-excel"
Write-Host "  flutter run"
