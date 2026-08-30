$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
  return Get-Content -Raw -Encoding UTF8 $Path
}
function Write-Utf8([string]$Path, [string]$Text) {
  Set-Content -Path $Path -Value $Text -Encoding UTF8
}
function Replace-Required([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  if (!$Text.Contains($Old)) {
    throw "Patch118 중단: '$Label' 기준 코드를 찾지 못했습니다. 현재 파일을 임의 수정하지 않았습니다."
  }
  return $Text.Replace($Old, $New)
}

$project = (Get-Location).Path

# ---------------------------------------------------------------------------
# 1) 엑셀 데이타 일괄 관리: 삭제 UI 문구만 간결하게 변경
# 기존 30일 삭제 대기 로직 자체는 그대로 유지
# ---------------------------------------------------------------------------
$excelBulk = Join-Path $project "lib\screens\excel_bulk_management_screen.dart"
Copy-Item $excelBulk "$excelBulk.bak_before_patch118" -Force
$src = Read-Utf8 $excelBulk

$src = Replace-Required $src `
  "title: const Text('화물 삭제 대기')," `
  "title: const Text('화물 삭제')," `
  "삭제 팝업 제목"

$oldContent = @'
            content: Text(
              '선택한 ${_checked.length}개 화물을 기존 삭제 로직과 동일하게 삭제 대기로 이동하시겠습니까?',
            ),
'@
$newContent = @'
            content: Text(
              '선택한 ${_checked.length}개의 화물을 삭제 합니다.\n\n'
              '30일 뒤에 자동으로 완전히 삭제 되며, 필요시 삭제 취소 혹은 바로 삭제가 가능 합니다.',
            ),
'@
$src = Replace-Required $src $oldContent $newContent "삭제 안내문"

$src = Replace-Required $src `
  "child: const Text('삭제 대기')," `
  "child: const Text('삭제')," `
  "삭제 확인 버튼"

$src = Replace-Required $src `
  "label: const Text('삭제 대기')," `
  "label: const Text('삭제')," `
  "상단 삭제 버튼"

# 처리 완료/실패 Snackbar도 사용자 문구를 단순화
$src = $src.Replace(
  "_message('선택한 화물을 삭제 대기로 이동했습니다.');",
  "_message('선택한 화물을 삭제 처리했습니다. 30일 동안 복구할 수 있습니다.');"
)
$src = $src.Replace(
  "_message('삭제 대기 처리 실패: `$error');",
  "_message('화물 삭제 처리 실패: `$error');"
)

Write-Utf8 $excelBulk $src
Write-Host "수정 완료: 엑셀 데이타 일괄 관리 삭제 문구"

# ---------------------------------------------------------------------------
# 2) 홈 상담 및 연락처: LK Group 사무실 위치 (Google Maps) 추가
# ---------------------------------------------------------------------------
$dashboard = Join-Path $project "lib\screens\dashboard_home_screen.dart"
Copy-Item $dashboard "$dashboard.bak_before_patch118" -Force
$src = Read-Utf8 $dashboard

$oldLinks = @'
  ContactLink(label: 'LK Group 블로그', icon: 'naver', placeholder: 'https://blog.naver.com/lkgrouplaos'),
];
'@
$newLinks = @'
  ContactLink(label: 'LK Group 블로그', icon: 'naver', placeholder: 'https://blog.naver.com/lkgrouplaos'),
  ContactLink(label: 'LK Group 사무실 위치', icon: 'google_maps', placeholder: 'https://maps.app.goo.gl/jMEFmjCw1wmJiAqx7'),
];
'@
$src = Replace-Required $src $oldLinks $newLinks "Google Maps 링크 추가"

$oldDefault = @'
      default:
        return const SizedBox(width: 24, height: 24);
'@
$newDefault = @'
      case 'google_maps':
        return Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.location_on_rounded,
            size: 19,
            color: Color(0xFF4285F4),
          ),
        );
      default:
        return const SizedBox(width: 24, height: 24);
'@
$src = Replace-Required $src $oldDefault $newDefault "Google Maps 아이콘"

Write-Utf8 $dashboard $src
Write-Host "수정 완료: 홈 LK Group 사무실 위치 링크"

Write-Host ""
Write-Host "Patch118 적용 완료"
Write-Host "- Excel 일괄관리: '삭제 대기' -> '삭제'"
Write-Host "- 삭제 확인 안내문 간결화"
Write-Host "- 기존 30일 자동 완전 삭제 / 삭제 취소 / 바로 삭제 로직은 변경하지 않음"
Write-Host "- 홈 상담 및 연락처에 'LK Group 사무실 위치' Google Maps 링크 추가"
Write-Host "- 회원/회사/할인/ID 로직은 이번 패치에서 건드리지 않음"
Write-Host "- SQL 없음"
