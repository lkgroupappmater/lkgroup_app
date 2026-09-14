import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/screens/cargo_receiving_search_screen.dart';
import 'package:lkgroup_app/widgets/submit_search_field.dart';

void main() {
  testWidgets('typing keeps focus and only button or keyboard submits', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final searches = <String>[];
    var rebuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              rebuilds++;
              return SubmitSearchField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Search'),
                onSearch: searches.add,
              );
            },
          ),
        ),
      ),
    );
    final buildsBeforeTyping = rebuilds;
    await tester.enterText(find.byType(TextField), '1');
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump(const Duration(seconds: 1));
    expect(searches, isEmpty);
    expect(rebuilds, buildsBeforeTyping);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(controller.selection.baseOffset, 5);

    await tester.tap(find.text('검색'));
    await tester.pump();
    expect(searches, ['12345']);
    await tester.enterText(find.byType(TextField), '홍길동');
    await tester.pump();
    expect(searches, ['12345']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(searches, ['12345', '홍길동']);
  });

  testWidgets('cargo results use the submitted query, including clearing it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CargoReceivingSearchScreen()),
    );
    final field = find.byType(TextField);
    expect(find.text('검색 결과가 없습니다.'), findsNothing);
    await tester.enterText(field, 'no-such-cargo-12345');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('검색 결과가 없습니다.'), findsNothing);
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없습니다.'), findsNothing);
  });
}
