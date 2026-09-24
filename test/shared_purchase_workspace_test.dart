import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/services/shared_purchase_workspace.dart';

void main() {
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
