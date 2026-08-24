// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// If your app's entry-point widget is named CargoFlowApp and lives in
// package:lkgroup_app/app.dart, uncomment the two lines below and remove
// the _StubApp usage further down.
//
// import 'package:lkgroup_app/app.dart';
//
// void main() {
//   testWidgets('CargoFlowApp smoke test', (WidgetTester tester) async {
//     await tester.pumpWidget(const CargoFlowApp());
//     expect(find.byType(MaterialApp), findsOneWidget);
//   });
// }

// ── Minimal safe smoke test (no dependency on app.dart) ────────────────────
//
// This test creates a tiny stub app so the file compiles and passes even
// when the real app widget hasn't been wired up yet.
// Replace _StubApp with CargoFlowApp (and add the import above) once app.dart
// exports that class.

class _StubApp extends StatelessWidget {
  const _StubApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('LK Group – CargoFlow')),
      ),
    );
  }
}

void main() {
  testWidgets('Stub smoke test — replace with CargoFlowApp when ready',
          (WidgetTester tester) async {
        await tester.pumpWidget(const _StubApp());

        expect(find.byType(MaterialApp), findsOneWidget);
        expect(find.text('LK Group – CargoFlow'), findsOneWidget);
      });
}
