import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/services/shared_purchase_workspace.dart';
import 'package:lkgroup_app/services/shared_ui_text_service.dart';

void main() {
  tearDown(() => SharedUiTextService.instance.applyRows([]));
  test('purchase and member-site labels use the same database keys as the web', () {
    SharedUiTextService.instance.applyRows([
      {'key': 'purchase.title', 'ko': '구매 서비스', 'en': 'Buying service', 'lo': 'ບໍລິການຊື້'},
      {'key': 'memberSites.title', 'ko': '내 사이트 계정', 'en': 'My shop accounts', 'lo': 'ບັນຊີຮ້ານຂອງຂ້ອຍ'},
    ]);
    expect(sharedPurchaseLabel(AppLanguage.korean, SharedPurchaseView.purchaseAgency), '구매 서비스');
    expect(sharedPurchaseLabel(AppLanguage.english, SharedPurchaseView.siteAccounts), 'My shop accounts');
  });
  test('shared purchase links use only the existing trusted site and identity guard', () {
    for (final view in SharedPurchaseView.values) {
      final uri = sharedPurchaseUri(memberId: 'test-member', language: AppLanguage.korean, view: view);
      expect(uri.origin, 'https://lkgrouptrading.com');
      expect(uri.queryParameters['lk_view'], view.name);
      expect(uri.queryParameters['member'], 'test-member');
      expect(uri.queryParameters.keys.toSet(), {'lk_view', 'lang', 'member'});
      expect(uri.userInfo, isEmpty);
    }
  });
  test('shared purchase entries have distinct Korean English Lao labels', () {
    for (final view in SharedPurchaseView.values) {
      final labels = AppLanguage.values.map((l) => sharedPurchaseLabel(l, view)).toSet();
      expect(labels.length, 3);
      expect(labels.every((label) => label.isNotEmpty), isTrue);
    }
  });
}
