import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_language.dart';

enum SharedPurchaseView { purchaseAgency, siteAccounts }

String sharedPurchaseLabel(AppLanguage language, SharedPurchaseView view) {
  final labels = view == SharedPurchaseView.purchaseAgency
      ? ['구매대행', 'Purchase agency', 'ບໍລິການຮັບຊື້']
      : ['내 외부 사이트 계정', 'My external site accounts', 'ບັນຊີເວັບໄຊຂອງຂ້ອຍ'];
  return labels[language == AppLanguage.korean ? 0 : language == AppLanguage.lao ? 2 : 1];
}

Uri sharedPurchaseUri({
  required String memberId,
  required AppLanguage language,
  required SharedPurchaseView view,
}) => Uri.https('lkgrouptrading.com', '/', {
  'lk_view': view.name,
  'lang': language.code,
  // An identity check only. No session token, login name or password in this URL.
  'member': memberId,
});

/// Both clients use the same authenticated editor, server calculation and export
/// renderer. Custom Tabs / Safari retain the site's own login and support downloads.
Future<void> openSharedPurchaseWorkspace(
  BuildContext context, {
  required String memberId,
  required AppLanguage language,
  required SharedPurchaseView view,
}) async {
  try {
    final uri = sharedPurchaseUri(memberId: memberId, language: language, view: view);
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened && !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Unable to open shared workspace');
    }
  } catch (_) {
    if (!context.mounted) return;
    final message = language == AppLanguage.korean
        ? '구매 화면을 열지 못했습니다. 다시 시도해 주세요.'
        : language == AppLanguage.lao
            ? 'ເປີດໜ້າຊື້ບໍ່ໄດ້. ກະລຸນາລອງອີກ.'
            : 'Could not open the purchase workspace. Please try again.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
