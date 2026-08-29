$ErrorActionPreference = 'Stop'

function Replace-Once([string]$text, [string]$old, [string]$new, [string]$label) {
  if ($text.Contains($new.Trim())) { return $text }
  if (!$text.Contains($old)) { throw "$label anchor not found" }
  return $text.Replace($old, $new)
}

# ------------------------------------------------------------
# shipment_search_screen.dart
# ------------------------------------------------------------
$path = "lib/screens/shipment_search_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("shipment_filter_options_service.dart")) {
  $anchor = "import '../services/shipment_service.dart';"
  if (!$text.Contains($anchor)) { throw "shipment search import anchor not found" }
  $text = $text.Replace(
    $anchor,
    "$anchor`r`nimport '../services/shipment_filter_options_service.dart';"
  )
}

if (!$text.Contains("List<ShipmentBatchOption> _filterBatches")) {
  $anchor = "  List<Map<String, dynamic>> _unknownRecipientRows = const [];"
  if (!$text.Contains($anchor)) { throw "shipment search state anchor not found" }
  $text = $text.Replace(
    $anchor,
    "$anchor`r`n  List<ShipmentBatchOption> _filterBatches = const [];"
  )
}

if (!$text.Contains("List<String> get _availableYears")) {
  $anchor = "  bool get _showZone => widget.currentUser?.role == UserRole.admin || widget.currentUser?.role == UserRole.staff;"
  if (!$text.Contains($anchor)) { throw "shipment search getter anchor not found" }
  $insert = @'

  List<String> get _availableYears {
    final route = routeLabels[_selectedRoute];
    final years =
        ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, route);
    return <String>['전체', ...years.map((e) => '$e년')];
  }

  List<String> get _availableVoyages {
    final route = routeLabels[_selectedRoute];
    final year =
        int.tryParse(_year.replaceAll(RegExp(r'[^0-9]'), ''));
    if (year == null) return const <String>['전체'];
    final voyages = ShipmentFilterOptionsService.instance
        .voyagesFor(_filterBatches, route, year);
    return <String>[
      '전체',
      ...voyages.map(
        (e) => e.endsWith('항차') ? e : '${e}항차',
      ),
    ];
  }

  Future<void> _loadFilterBatches() async {
    if (!widget.isLoggedIn || widget.currentUser == null) return;
    try {
      final rows = await ShipmentFilterOptionsService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _filterBatches = rows;
        if (!_availableYears.contains(_year)) _year = '전체';
        if (!_availableVoyages.contains(_voyage)) _voyage = '전체';
      });
    } catch (_) {
      // 조회 필터 목록 실패가 기존 화물 조회 자체를 막지 않도록 합니다.
    }
  }
'@
  $text = $text.Replace($anchor, $anchor + $insert)
}

# initState load
if (!$text.Contains("_loadFilterBatches();")) {
  $anchor = "    _loadUnknownRecipientCargo();"
  $idx = $text.IndexOf($anchor)
  if ($idx -lt 0) { throw "shipment search init load anchor not found" }
  $text = $text.Substring(0,$idx) + $anchor + "`r`n    _loadFilterBatches();" + $text.Substring($idx+$anchor.Length)
}

# didUpdateWidget also reload
$didMarker = "if (oldWidget.currentUser?.id != widget.currentUser?.id)"
$didIdx = $text.IndexOf($didMarker)
if ($didIdx -ge 0) {
  $closeIdx = $text.IndexOf("    }", $didIdx)
  $segment = $text.Substring($didIdx, $closeIdx-$didIdx)
  if (!$segment.Contains("_loadFilterBatches();")) {
    $target = "    _loadUnknownRecipientCargo();"
    $p = $text.IndexOf($target,$didIdx)
    if ($p -ge 0 -and $p -lt $closeIdx) {
      $text = $text.Substring(0,$p) + $target + "`r`n      _loadFilterBatches();" + $text.Substring($p+$target.Length)
    }
  }
}

# route onChanged reset year/voyage
$pattern = "(?ms)onChanged:\s*\(value\)\s*\{\s*if \(value != null\) setState\(\(\) => _selectedRoute = value\);\s*\},"
if ([regex]::IsMatch($text,$pattern)) {
  $replacement = @'
onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedRoute = value;
                  _year = '전체';
                  _voyage = '전체';
                });
              }
            },
'@
  $text = [regex]::Replace($text,$pattern,$replacement,1)
}

# year hardcoded items -> dynamic
$pattern = "(?ms)items:\s*const \['전체', '2026년', '2027년', '2028년'\]\s*\.map\(\(v\) => DropdownMenuItem\(value: v, child: Text\(v\)\)\)\s*\.toList\(\),"
if ([regex]::IsMatch($text,$pattern)) {
  $text = [regex]::Replace(
    $text,$pattern,
    "items: _availableYears`r`n                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))`r`n                      .toList(),",
    1
  )
}

# year change resets voyage
$pattern = "(?ms)onChanged:\s*\(v\)\s*\{\s*if \(v != null\) setState\(\(\) => _year = v\);\s*\},"
if ([regex]::IsMatch($text,$pattern)) {
  $replacement = @'
onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _year = v;
                        _voyage = '전체';
                      });
                    }
                  },
'@
  $text = [regex]::Replace($text,$pattern,$replacement,1)
}

# voyage generated 30 -> actual data list
$pattern = "(?ms)items:\s*<String>\[\s*'전체',\s*\.\.\.List\.generate\(\s*30,\s*\(i\) => '\$\{\(i \+ 1\)\.toString\(\)\.padLeft\(2, '0'\)\}항차',\s*\),\s*\]\.map\(\(v\) => DropdownMenuItem\(value: v, child: Text\(v\)\)\)\.toList\(\),"
if ([regex]::IsMatch($text,$pattern)) {
  $text = [regex]::Replace(
    $text,$pattern,
    "items: _availableVoyages`r`n                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))`r`n                      .toList(),",
    1
  )
}

Set-Content -Path $path -Value $text -Encoding UTF8

# ------------------------------------------------------------
# cargo_management_screen.dart
# ------------------------------------------------------------
$path = "lib/screens/cargo_management_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("shipment_filter_options_service.dart")) {
  $anchor = "import '../services/shipment_service.dart';"
  if (!$text.Contains($anchor)) { throw "cargo import anchor not found" }
  $text = $text.Replace(
    $anchor,
    "$anchor`r`nimport '../services/shipment_filter_options_service.dart';"
  )
}

if (!$text.Contains("List<ShipmentBatchOption> _filterBatches")) {
  $anchor = "  List<Map<String, dynamic>> _pendingDeletions = const [];"
  if (!$text.Contains($anchor)) { throw "cargo state anchor not found" }
  $text = $text.Replace(
    $anchor,
    "$anchor`r`n  List<ShipmentBatchOption> _filterBatches = const [];"
  )
}

if (!$text.Contains("List<String> get _availableYears")) {
  $anchor = "  bool get _canSaveDirectly => _isManager;"
  if (!$text.Contains($anchor)) { throw "cargo getter anchor not found" }
  $insert = @'

  List<String> get _availableYears {
    final years =
        ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, _route);
    return <String>['전체', ...years.map((e) => '$e년')];
  }

  List<String> get _availableVoyages {
    final year =
        int.tryParse(_year.replaceAll(RegExp(r'[^0-9]'), ''));
    if (year == null) return const <String>['전체'];
    final voyages = ShipmentFilterOptionsService.instance
        .voyagesFor(_filterBatches, _route, year);
    return <String>[
      '전체',
      ...voyages.map(
        (e) => e.endsWith('항차') ? e : '${e}항차',
      ),
    ];
  }

  Future<void> _loadFilterBatches() async {
    try {
      final rows = await ShipmentFilterOptionsService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _filterBatches = rows;
        if (!_availableYears.contains(_year)) _year = '전체';
        if (!_availableVoyages.contains(_voyage)) _voyage = '전체';
      });
    } catch (_) {
      // 공통 조회 옵션 실패가 기존 화물 관리 기능을 막지 않도록 합니다.
    }
  }
'@
  $text = $text.Replace($anchor,$anchor+$insert)
}

# cargo init
$initAnchor = "    _selectedIds.addAll(widget.initialSelectedIds);"
$idx = $text.IndexOf($initAnchor)
if ($idx -lt 0) { throw "cargo init anchor not found" }
$after = $idx+$initAnchor.Length
$near = $text.Substring($idx,[Math]::Min(300,$text.Length-$idx))
if (!$near.Contains("_loadFilterBatches();")) {
  $text = $text.Substring(0,$after) + "`r`n    _loadFilterBatches();" + $text.Substring($after)
}

# cargo route change reset filters
$old = @'
                  setState(() {
                    _route = value;
                    _boxNumberController.clear();
                  });
'@
$new = @'
                  setState(() {
                    _route = value;
                    _year = '전체';
                    _voyage = '전체';
                    _boxNumberController.clear();
                  });
'@
if ($text.Contains($old)) { $text = $text.Replace($old,$new) }

# cargo hardcoded years
$pattern = "(?ms)items:\s*const \['전체', '2026년', '2027년', '2028년'\]\s*\.map\(\(v\) => DropdownMenuItem\(value: v, child: Text\(v\)\)\)\s*\.toList\(\),"
if ([regex]::IsMatch($text,$pattern)) {
  $text = [regex]::Replace(
    $text,$pattern,
    "items: _availableYears`r`n                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))`r`n                        .toList(),",
    1
  )
}

# cargo year change reset voyage
$pattern = "(?ms)onChanged:\s*\(v\)\s*\{\s*if \(v != null\) setState\(\(\) => _year = v\);\s*\},"
if ([regex]::IsMatch($text,$pattern)) {
  $replacement = @'
onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _year = v;
                          _voyage = '전체';
                        });
                      }
                    },
'@
  $text = [regex]::Replace($text,$pattern,$replacement,1)
}

# cargo generated voyages
$pattern = "(?ms)items:\s*<String>\[\s*'전체',\s*\.\.\.List\.generate\(\s*30,\s*\(i\) => '\$\{\(i \+ 1\)\.toString\(\)\.padLeft\(2, '0'\)\}항차',\s*\),\s*\]\.map\(\(v\) => DropdownMenuItem\(value: v, child: Text\(v\)\)\)\.toList\(\),"
if ([regex]::IsMatch($text,$pattern)) {
  $text = [regex]::Replace(
    $text,$pattern,
    "items: _availableVoyages`r`n                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))`r`n                        .toList(),",
    1
  )
}

Set-Content -Path $path -Value $text -Encoding UTF8

Write-Host "공통 조회 구조 패치 완료."
Write-Host "Supabase 049 SQL 실행 후 flutter analyze 하세요."
