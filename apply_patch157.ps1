$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count=([regex]::Matches($text,[regex]::Escape($old))).Count
  if($count -ne 1){ throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}
function ReplaceRange([string]$text,[string]$start,[string]$end,[string]$replacement,[string]$label) {
  $s=$text.IndexOf($start)
  $e=$text.IndexOf($end,$s+$start.Length)
  if($s -lt 0 -or $e -le $s){ throw "안전 중단 [$label]" }
  return $text.Substring(0,$s)+$replacement+$text.Substring($e)
}

# ============================================================
# 1) Excel bulk management
# ============================================================
$p="lib/screens/excel_bulk_management_screen.dart"
$t=ReadText $p

# state + visible rows
$t=ReplaceOnce $t @'
  bool _busy = true;
'@ @'
  bool _busy = true;
  bool _lockedOnly = false;

  List<Map<String, dynamic>> get _visibleRows => _lockedOnly
      ? _rows.where((e) => e['data_locked'] == true).toList(growable: false)
      : _rows;

  int get _lockedCount =>
      _rows.where((e) => e['data_locked'] == true).length;
'@ "bulk locked state"

# loadRows: filter auto-off if no locks
$t=ReplaceOnce $t @'
      setState(() {
        _rows = rows;
        _checked.clear();
      });
'@ @'
      setState(() {
        _rows = rows;
        _checked.clear();
        if (_lockedOnly && !rows.any((e) => e['data_locked'] == true)) {
          _lockedOnly = false;
        }
        if (_lockedOnly) {
          _checked.addAll(
            rows
                .where((e) => e['data_locked'] == true)
                .map((e) => '${e['id']}'),
          );
        }
      });
'@ "bulk load locked filter"

# toggleAll acts on visible rows
$t=ReplaceOnce $t @'
  void _toggleAll(bool checked) {
    setState(() {
      if (checked) {
        _checked
          ..clear()
          ..addAll(_rows.map((e) => '${e['id']}'));
      } else {
        _checked.clear();
      }
    });
  }
'@ @'
  void _toggleAll(bool checked) {
    final visible = _visibleRows;
    setState(() {
      if (checked) {
        _checked
          ..clear()
          ..addAll(visible.map((e) => '${e['id']}'));
      } else {
        _checked.clear();
      }
    });
  }

  void _toggleLockedOnly() {
    if (_lockedOnly) {
      setState(() {
        _lockedOnly = false;
        _checked.clear();
      });
      return;
    }

    final locked = _rows.where((e) => e['data_locked'] == true).toList();
    if (locked.isEmpty) {
      _message('현재 잠금된 화물이 없습니다.');
      return;
    }
    setState(() {
      _lockedOnly = true;
      _checked
        ..clear()
        ..addAll(locked.map((e) => '${e['id']}'));
    });
  }

  Future<void> _unlockSingle(Map<String, dynamic> row) async {
    if (_busy || row['data_locked'] != true) return;
    final id = '${row['id']}';
    setState(() => _busy = true);
    try {
      await ExcelBulkManagementService.instance.setLocked([id], false);
      if (!mounted) return;
      setState(() {
        row['data_locked'] = false;
        _checked.remove(id);
        if (_lockedOnly &&
            !_rows.any((e) => e['data_locked'] == true)) {
          _lockedOnly = false;
        }
      });
      _message('해당 화물 잠금을 해제했습니다.');
    } catch (error) {
      _message('잠금 해제 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
'@ "bulk toggle/filter methods"

# build: use visible rows
$t=ReplaceOnce $t @'
    final allChecked =
        _rows.isNotEmpty && _checked.length == _rows.length;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
'@ @'
    final visibleRows = _visibleRows;
    final visibleIds = visibleRows.map((e) => '${e['id']}').toSet();
    final allChecked = visibleIds.isNotEmpty && _checked.containsAll(visibleIds);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in visibleRows) {
'@ "bulk build visible rows"

# empty/list condition use visible rows but preserve source empty semantics
$t=ReplaceOnce $t @'
                    : _rows.isEmpty
                        ? const Center(
                            child: Text('해당 항차 화물 데이터가 없습니다.'),
                          )
                        : ListView(
'@ @'
                    : _rows.isEmpty
                        ? const Center(
                            child: Text('해당 항차 화물 데이터가 없습니다.'),
                          )
                        : visibleRows.isEmpty
                            ? const Center(
                                child: Text('현재 조건에 해당하는 화물이 없습니다.'),
                              )
                            : ListView(
'@ "bulk visible empty"

# selection text show locked filter state compactly
$t=ReplaceOnce $t @'
                    child: Text(
                      '선택 ${_checked.length}개',
'@ @'
                    child: Text(
                      _lockedOnly
                          ? '잠금만 보기 · ${_lockedCount}개'
                          : '선택 ${_checked.length}개',
'@ "bulk locked caption"

# bottom lock action: red + toggle behavior
$t=ReplaceOnce $t @'
                      _bulkBarAction(
                        icon: Icons.lock_outline,
                        label: '잠금',
                        enabled: _checked.isNotEmpty && !_busy,
                        onTap: () => _setLock(true),
                      ),
'@ @'
                      _bulkBarAction(
                        icon: _lockedOnly ? Icons.lock : Icons.lock_outline,
                        label: _lockedOnly ? '잠금만' : '잠금',
                        enabled: _lockedCount > 0 || _checked.isNotEmpty,
                        forceRed: true,
                        onTap: () {
                          if (_lockedOnly || _checked.isEmpty) {
                            _toggleLockedOnly();
                          } else {
                            _setLock(true);
                          }
                        },
                      ),
'@ "bulk lock bar behavior"

# helper gets forceRed
$t=ReplaceOnce $t @'
  Widget _bulkBarAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
'@ @'
  Widget _bulkBarAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool forceRed = false,
  }) =>
'@ "bulk bar forceRed arg"

$t=ReplaceOnce $t @'
                color: enabled ? AppColors.tealAccent : Colors.white38,
'@ @'
                color: !enabled
                    ? Colors.white38
                    : forceRed
                        ? Colors.redAccent
                        : AppColors.tealAccent,
'@ "bulk bar red icon"

# row lock icon becomes tappable red unlock control
$old=@'
              if (locked)
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: 2),
                  child: Icon(
                    Icons.lock,
                    color: Colors.redAccent,
                    size: 17,
                  ),
                ),
'@
$new=@'
              if (locked)
                IconButton(
                  tooltip: '잠금 해제',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _unlockSingle(row),
                  icon: const Icon(
                    Icons.lock,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                ),
'@
$t=ReplaceOnce $t $old $new "bulk row clickable red lock"

WriteText $p $t

# ============================================================
# 2) Shipment search bottom bar -> same consultation style
# ============================================================
$p="lib/screens/shipment_search_screen.dart"
$t=ReadText $p

$start="  Widget _searchFixedBottomBar() {"
$end="`n  @override`n  Widget build(BuildContext context)"
$replacement=@'
  Widget _searchFixedBottomBar() {
    final allSelected = _results.isNotEmpty &&
        _selectedIds.containsAll(_results.map((r) => '${r['id']}'));

    Widget divider() => Container(
          width: 1,
          height: 34,
          color: Colors.white.withValues(alpha: .16),
        );

    Widget action({
      required IconData icon,
      required String label,
      required bool enabled,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(15),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: enabled ? AppColors.tealAccent : Colors.white38,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        );

    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(22),
      color: Colors.transparent,
      shadowColor: Colors.black38,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.navyPrimary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              action(
                icon: allSelected
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                label: '전체',
                enabled: _results.isNotEmpty,
                onTap: _toggleAll,
              ),
              divider(),
              action(
                icon: Icons.price_check_outlined,
                label: '운임 확인',
                enabled: _selectedIds.isNotEmpty,
                onTap: _showFreight,
              ),
              divider(),
              action(
                icon: Icons.inventory_2_outlined,
                label: '화물 관리',
                enabled:
                    _selectedIds.isNotEmpty && widget.onManageSelected != null,
                onTap: () => widget.onManageSelected!(
                  _selectedIds.toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
'@
$t=ReplaceRange $t $start $end $replacement "search consultation bar"
WriteText $p $t

Write-Host ""
Write-Host "Patch157 적용 완료"
Write-Host "- Excel 일괄관리 잠금 아이콘 전체 빨강"
Write-Host "- 각 빨간 잠금 아이콘 클릭 -> 해당 화물만 해제"
Write-Host "- 선택 없음 + 하단 잠금 -> 잠긴 화물만 보기/전체체크 토글"
Write-Host "- 잠금만 보기 상태에서 개별 해제 -> 즉시 화면에서 사라짐"
Write-Host "- 잠긴 화물 0건 -> 잠금만 보기 자동 종료"
Write-Host "- 영수번호 그룹 구조 그대로 유지"
Write-Host "- 화물조회 하단 UI를 화물관리/Excel과 동일 상담바 스타일로 통일"
Write-Host ""
Write-Host "다음: flutter analyze"
