$ErrorActionPreference = "Stop"

# quote_request_screen.dart
$q = "lib/screens/quote_request_screen.dart"
$text = Get-Content $q -Raw -Encoding UTF8
$text = $text -replace "(?s)\s*// Simulated login state\s*// TODO: Replace with real AuthController\.isLoggedIn\s*bool _isLoggedIn = false;", ""
$text = $text -replace "if \(!_isLoggedIn\) \{", "if (Supabase.instance.client.auth.currentUser == null) {"
$text = $text -replace "(?s)\s*// Mock login toggle for testing\s*const SizedBox\(height: 16\),\s*Row\(\s*children: \[\s*Checkbox\(\s*value: _isLoggedIn,\s*activeColor: AppColors\.navyPrimary,\s*onChanged: \(v\) =>\s*setState\(\(\) => _isLoggedIn = v \?\? false\),\s*\),\s*const Text\('\[테스트\] 로그인 상태로 전환',\s*style: TextStyle\(\s*fontSize: 12, color: AppColors\.textSecondary\)\),\s*\],\s*\),", ""
if ($text -match "\[테스트\] 로그인 상태로 전환") {
  throw "quote_request_screen.dart 패턴 적용 실패: 테스트 로그인 문구가 남아 있습니다."
}
Set-Content $q $text -Encoding UTF8

# cargo_management_screen.dart:
# 기존 화면 구조는 그대로 두고 상단 프로필의 실제 avatar_url + 한글 roleLabel만 적용.
$c = "lib/screens/cargo_management_screen.dart"
$text = Get-Content $c -Raw -Encoding UTF8
$text = $text -replace "leading: const CircleAvatar\(child: Icon\(Icons\.person\)\),", @'
leading: CircleAvatar(
                backgroundImage: widget.user.avatarUrl != null &&
                        widget.user.avatarUrl!.trim().isNotEmpty
                    ? NetworkImage(widget.user.avatarUrl!)
                    : null,
                child: widget.user.avatarUrl == null ||
                        widget.user.avatarUrl!.trim().isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
'@
if ($text -notmatch "backgroundImage: widget.user.avatarUrl") {
  throw "cargo_management_screen.dart 패턴 적용 실패: 프로필 사진 코드가 적용되지 않았습니다."
}
Set-Content $c $text -Encoding UTF8

Write-Host "Small patches applied."
