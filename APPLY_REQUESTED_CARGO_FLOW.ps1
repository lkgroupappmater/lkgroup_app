$ErrorActionPreference = "Stop"

$path = Join-Path $PSScriptRoot "lib\screens\cargo_management_screen.dart"
if (-not (Test-Path $path)) {
  throw "cargo_management_screen.dart 파일을 찾을 수 없습니다."
}

$content = [System.IO.File]::ReadAllText($path)
$backup = "$path.bak_038"
[System.IO.File]::WriteAllText($backup, $content, [System.Text.UTF8Encoding]::new($false))

# 1) _search 함수 전체를 함수 경계 기준으로 교체
$searchPattern = '(?s)  Future<void> _search\(\) async \{.*?\r?\n  \}\r?\n\r?\n  void _toggle'
$searchMatch = [regex]::Match($content, $searchPattern)
if (-not $searchMatch.Success) {
  throw "_search 함수 경계를 찾지 못했습니다. 원본은 변경하지 않았습니다. 백업: $backup"
}

$newSearch = @'
  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final rows = await ShipmentService.instance.searchRows(
        route: _route,
        boxNumber: _showBoxSearch ? _boxNumberForRequest() : '',
        invoice: _showInvoiceSearch ? _invoiceController.text.trim() : '',
        recipient: _showNameSearch ? _nameController.text.trim() : '',
        phone: _showPhoneSearch ? _phoneController.text.trim() : '',
        year: _year,
        voyage: _voyage,
        currentUser: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searched = true;
        if (widget.initialSelectedIds.isEmpty) _selectedIds.clear();
      });
      _syncEditControllers();

      if (_isManager && rows.isEmpty) {
        final add = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: const Text(
              '검색 하신 화물 데이타가 없습니다. 화물을 추가 하시겠습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('화물 추가 입력'),
              ),
            ],
          ),
        );
        if (add == true && mounted) {
          await _openManualAdd(
            route: _route,
            year: _year,
            voyage: _voyage,
            invoice: _invoiceController.text.trim(),
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
        }
      }
    } catch (error) {
      _message('화물 검색 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openManualAdd({
    String? route,
    String? year,
    String? voyage,
    String invoice = '',
    String name = '',
    String phone = '',
  }) async {
    final parsedYear = year == null || year == '전체'
        ? null
        : int.tryParse(year.replaceAll(RegExp(r'[^0-9]'), ''));
    final selectedVoyage =
        voyage == null || voyage == '전체' ? null : voyage;

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentManualAddScreen(
          initialRoute: route,
          initialYear: parsedYear,
          initialVoyage: selectedVoyage,
          initialInvoice: invoice,
          initialName: name,
          initialPhone: phone,
        ),
      ),
    );
    if (added == true && mounted) {
      await _search();
    }
  }

  void _toggle
'@

$content = [regex]::Replace($content, $searchPattern, $newSearch, 1)

# 2) "화물 추가 입력" 버튼이 들어있는 OutlinedButton.icon의 onPressed 블록만 교체
# 현재 V3 형태: onPressed: _busy || ... ? null : () async { ... },
$buttonPattern = '(?s)onPressed:\s*_busy\s*\|\|\s*_year\s*==\s*''전체''\s*\|\|\s*_voyage\s*==\s*''전체''\s*\?\s*null\s*:\s*\(\)\s*async\s*\{.*?\},\s*(?=icon:\s*const Icon\(Icons\.add_box_outlined\))'
$buttonMatch = [regex]::Match($content, $buttonPattern)
if (-not $buttonMatch.Success) {
  throw "화물 추가 입력 버튼의 기존 onPressed 블록을 찾지 못했습니다. 백업에서 복원할 수 있습니다: $backup"
}
$content = [regex]::Replace(
  $content,
  $buttonPattern,
  "onPressed: _busy ? null : () => _openManualAdd(),`r`n                        ",
  1
)

[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "cargo_management_screen.dart 요청 변경 완료"
Write-Host "백업 파일: $backup"
