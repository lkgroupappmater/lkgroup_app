import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/domestic_tracking_text.dart';
import 'package:lkgroup_app/models/app_user.dart';
import 'package:lkgroup_app/services/shared_ui_text_service.dart';
import 'package:lkgroup_app/widgets/tracking_choice_sheet.dart';

void main() {
  tearDown(() => SharedUiTextService.instance.applyRows([]));
  test('every language separates public titles from operational titles', () {
    for (final language in AppLanguage.values) {
      for (final role in [null, UserRole.guest, UserRole.member]) {
        expect(domesticTitle(language, role), domesticText(language, 'publicTitle'));
      }
      for (final role in [UserRole.admin, UserRole.staff, UserRole.partner]) {
        expect(domesticTitle(language, role), domesticText(language, 'title'));
      }
      expect(domesticText(language, 'manage'), domesticText(language, 'title'));
      expect(domesticText(language, 'publicTitle'), isNot(domesticText(language, 'title')));
    }
  });
  for (final choice in TrackingChoice.values) {
    testWidgets('bottom sheet returns $choice and updates shared copy while open', (tester) async {
      TrackingChoice? selected;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () async {
          selected = await showTrackingChoiceSheet(context, AppLanguage.korean, UserRole.member);
        }, child: const Text('open')),
      ))));
      await tester.tap(find.text('open')); await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text(domesticText(AppLanguage.korean, 'title')), findsNothing);
      SharedUiTextService.instance.applyRows([{'key':'domestic.publicTitle','ko':'고객 배송 조회'}]);
      await tester.pump();
      expect(find.text('고객 배송 조회'), findsOneWidget);
      await tester.tap(find.byType(ListTile).at(choice == TrackingChoice.cargo ? 0 : 1));
      await tester.pumpAndSettle();
      expect(selected, choice); expect(find.byType(ListTile), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
