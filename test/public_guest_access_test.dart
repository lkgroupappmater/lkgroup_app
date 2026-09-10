import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/widgets/app_shell.dart';

void main() {
  testWidgets('guest can open the public information home', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pumpAndSettle();

    expect(find.text('선적 일정'), findsWidgets);
    expect(find.text('공지 및 안내'), findsWidgets);
    expect(find.text('회사 소개·활동·자료실'), findsOneWidget);

    // Account-only and administrator-only navigation stays unavailable.
    expect(find.text('화물 관리'), findsNothing);
    expect(find.text('관리 메뉴'), findsNothing);
  });

  testWidgets(
    'guest can open freight check and estimate controls',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('운임 확인').last);
      await tester.pumpAndSettle();

      expect(find.text('박스 정보 입력'), findsOneWidget);
      expect(find.text('견적서 보기'), findsOneWidget);
      expect(find.text('대량 혹은 특수 견적 요청'), findsOneWidget);
    },
  );
}
