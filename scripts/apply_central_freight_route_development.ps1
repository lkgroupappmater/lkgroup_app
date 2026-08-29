$ErrorActionPreference='Stop'
# Quote calculator call becomes async.
$p="lib/screens/quote_request_screen.dart"; $t=Get-Content -Raw -Encoding UTF8 $p
$t=$t.Replace("final result = QuoteFreightCalculator.calculate(","final result = await QuoteFreightCalculator.calculate(")
Set-Content $p $t -Encoding UTF8

# Admin-only management menu item.
$p="lib/screens/management_menu_screen.dart"; $t=Get-Content -Raw -Encoding UTF8 $p
if(!$t.Contains("additional_feature_development_screen.dart")){
 $a="import 'change_approval_screen.dart';"; if(!$t.Contains($a)){throw "management import anchor not found"}
 $t=$t.Replace($a,"$a`r`nimport 'additional_feature_development_screen.dart';")
}
if(!$t.Contains("'label': '추가 기능 개발'")){
 $a=@"
        {
          'label': '회원 종합 관리',
"@
 $n=@"
        {
          'label': '추가 기능 개발',
          'icon': Icons.developer_mode_outlined,
          'page': const AdditionalFeatureDevelopmentScreen(),
        },
        {
          'label': '회원 종합 관리',
"@
 if(!$t.Contains($a)){throw "admin menu anchor not found"};$t=$t.Replace($a,$n)
}
Set-Content $p $t -Encoding UTF8
Write-Host "중앙 운임 + 추가 기능 개발 패치 완료"
