$ErrorActionPreference = "Stop"

$path = Join-Path $PSScriptRoot "lib\screens\cargo_management_screen.dart"
if (-not (Test-Path $path)) {
  throw "lib\screens\cargo_management_screen.dart 파일을 찾을 수 없습니다. 이 스크립트를 프로젝트 루트에서 실행하세요."
}

$content = [System.IO.File]::ReadAllText($path)

$importOld = @"
import '../services/shipment_service.dart';
import 'notice_management_screen.dart';
"@
$importNew = @"
import '../services/shipment_service.dart';
import 'shipment_manual_add_screen.dart';
import 'notice_management_screen.dart';
"@

if (-not $content.Contains($importOld)) {
  throw "import 기준 문자열이 최신 파일과 일치하지 않습니다. 파일은 변경하지 않았습니다."
}
$content = $content.Replace($importOld, $importNew)

$buttonOld = @"
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
                label: Text(_busy ? '검색 중...' : '화물 검색'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _showAddShipmentRowDialog,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('박스 추가 (행 추가)'),
              ),
            ],
"@

$buttonNew = @"
            if (_isManager)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _search,
                        icon: const Icon(Icons.search),
                        label: Text(_busy ? '검색 중...' : '화물 검색'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _busy || _year == '전체' || _voyage == '전체'
                            ? null
                            : () async {
                                final year = int.tryParse(
                                  _year.replaceAll(RegExp(r'[^0-9]'), ''),
                                );
                                if (year == null) return;
                                final added = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ShipmentManualAddScreen(
                                      route: _route,
                                      year: year,
                                      voyage: _voyage,
                                    ),
                                  ),
                                );
                                if (added == true && mounted) await _search();
                              },
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('화물 추가 입력'),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: Text(_busy ? '검색 중...' : '화물 검색'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
"@

if (-not $content.Contains($buttonOld)) {
  throw "화물 검색/박스 추가 기준 문자열이 최신 파일과 일치하지 않습니다. 파일은 변경하지 않았습니다."
}
$content = $content.Replace($buttonOld, $buttonNew)

[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "cargo_management_screen.dart 요청 부분만 수정 완료"
