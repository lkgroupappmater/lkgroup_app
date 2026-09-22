import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/approval_batch.dart';
import 'package:lkgroup_app/services/approval_batch_service.dart';
import 'package:lkgroup_app/widgets/approval_batch_editor.dart';

ApprovalItem change(int id, String name) => ApprovalItem(ApprovalKind.changes, {
  'request_id': id,
  'box_number': 'S$id',
  'consignee_name': 'old',
  'requested_changes': {'consignee_name': name, 'quantity': 2},
});

void main() {
  test('Zone review starts with Excel values and permits reverting explicitly', () {
    final draft = ApprovalDraft(ApprovalItem(ApprovalKind.changes, {
      'request_id': 1,
      'unloading_zone': 'F',
      'weight_kg': 3,
      'requested_changes': {'unloading_zone': 'C'},
    }));
    expect(draft.values['unloading_zone'], 'C');
    expect(draft.payload(), isEmpty);
    draft.values['unloading_zone'] = 'F';
    expect(draft.payload(), {'unloading_zone': 'F'});
    draft.values['unloading_zone'] = 'ST';
    expect(draft.payload(), {'unloading_zone': 'ST'});
  });

  test(
    'competing claims are reported together instead of approving the first',
    () {
      final one = ApprovalItem(ApprovalKind.invoiceClaims, {
        'request_id': 1,
        'shipment_id': 9,
      });
      final two = ApprovalItem(ApprovalKind.invoiceClaims, {
        'request_id': 2,
        'shipment_id': 9,
      });
      final three = ApprovalItem(ApprovalKind.invoiceClaims, {
        'request_id': 3,
        'shipment_id': 10,
      });
      expect(conflictingApprovalKeys([one, two, three], 'approve'), {
        one.key,
        two.key,
      });
      expect(conflictingApprovalKeys([one, two], 'reject'), isEmpty);
      expect(conflictingApprovalKeys([one, three], 'approve'), isEmpty);
    },
  );

  test(
    'per-row edits preserve requests and send only actual admin overrides',
    () {
      final first = ApprovalDraft(change(1, 'Alice'));
      final second = ApprovalDraft(change(2, 'Bob'));
      expect(first.values['consignee_name'], 'Alice');
      expect(second.values['consignee_name'], 'Bob');
      first.values['consignee_phone'] = '12345';
      expect(first.payload(), {'consignee_phone': '12345'});
      expect(second.payload(), isEmpty);
      first.values['quantity'] = '1.5';
      expect(first.payload, throwsFormatException);
      first.values['quantity'] = 'Infinity';
      expect(first.payload, throwsFormatException);
    },
  );

  test(
    'batch continues after failure, deduplicates and reports exact IDs',
    () async {
      final calls = <String>[];
      final one = change(1, 'A'), two = change(2, 'B'), three = change(3, 'C');
      final result = await processApprovalBatch(
        items: [one, two, three, one],
        canContinue: () => true,
        worker: (item) async {
          calls.add(item.key);
          if (item.id == '2') throw StateError('already reviewed');
        },
      );
      expect(calls, [one.key, two.key, three.key]);
      expect(result.succeeded, {one.key, three.key});
      expect(result.failures.keys, [two.key]);
      final selected = {one.key, two.key, three.key}
        ..removeAll(result.succeeded);
      expect(selected, {two.key});
    },
  );

  test('session change stops unsent items', () async {
    var active = true;
    final result = await processApprovalBatch(
      items: [change(1, 'A'), change(2, 'B')],
      canContinue: () => active,
      worker: (_) async {
        active = false;
      },
    );
    expect(result.succeeded, {'changes:1'});
    expect(result.failures.keys, ['changes:2']);
  });

  test('same numeric ID in separate approval types never collides', () {
    expect(
      change(1, 'A').key,
      isNot(ApprovalItem(ApprovalKind.unknownClaims, {'claim_id': 1}).key),
    );
  });

  test(
    'correct RPCs, per-row changes and existing approval rules are reused',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = ApprovalBatchService(
        rpc: (name, params) async {
          calls.add({'name': name, ...params});
        },
      );
      await service.apply(
        change(1, 'A'),
        'modified_approve',
        changes: {'consignee_phone': '123'},
      );
      await service.apply(
        ApprovalItem(ApprovalKind.invoiceClaims, {'request_id': 2}),
        'approve',
      );
      await service.apply(
        ApprovalItem(ApprovalKind.unknownClaims, {'claim_id': 3}),
        'reject',
      );
      await service.apply(
        ApprovalItem(ApprovalKind.autoUnmatched, {'queue_id': 4}),
        'keep',
      );
      expect(calls[0]['p_admin_changes'], {'consignee_phone': '123'});
      expect(calls.map((c) => c['name']), [
        'review_shipment_change_request',
        'admin_review_invoice_correction_request',
        'admin_review_unknown_recipient_claim',
        'admin_keep_auto_unmatched_recipient',
      ]);
      await expectLater(
        service.apply(
          ApprovalItem(ApprovalKind.invoiceClaims, {'request_id': 2}),
          'modified_approve',
        ),
        throwsStateError,
      );
      expect(calls.length, 4);
    },
  );

  test(
    'duplicate receipt blocks only that cargo and never applies a suggestion',
    () async {
      final calls = <String>[];
      final service = ApprovalBatchService(
        rpc: (name, params) async {
          calls.add(name);
          if (name == 'admin_check_receipt_number')
            return {'duplicate': true, 'suggested_receipt': 'LKS 09'};
        },
      );
      await expectLater(
        service.apply(
          ApprovalItem(ApprovalKind.incomplete, {
            'shipment_id': '9',
            'receipt_number': 'LKS 08',
          }),
          'complete',
        ),
        throwsStateError,
      );
      expect(calls, ['admin_check_receipt_number']);
    },
  );

  test('incomplete confirmation preserves its own fields and locks only on request', () async {
    final calls = <Map<String, dynamic>>[];
    final cleared = <String>[];
    final service = ApprovalBatchService(
      rpc: (name, params) async {
        calls.add({'name': name, ...params});
        return {'duplicate': false};
      },
      clearManualUncertain: (id) async {
        cleared.add(id);
      },
    );
    await service.apply(
      ApprovalItem(ApprovalKind.incomplete, {
        'shipment_id': '9',
        'consignee_name': 'Alice',
        'receipt_number': 'LKS 08',
        'manual_uncertain': true,
      }),
      'complete',
    );
    expect(calls.last['p_consignee_name'], 'Alice');
    expect(calls.last['p_receipt_number'], 'LKS 08');
    expect(calls.last['p_lock'], true);
    expect(cleared, ['9']);
  });

  testWidgets('one editor submits independent edits for every selected row', (
    tester,
  ) async {
    Map<String, Map<String, dynamic>>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                submitted = await showDialog<Map<String, Map<String, dynamic>>>(
                  context: context,
                  builder: (_) => ApprovalBatchEditor(
                    items: [change(1, 'Alice'), change(2, 'Bob')],
                    savedDrafts: const {},
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('changes:1:consignee_name')),
      'Alice corrected',
    );
    await tester.tap(find.text('수정 후 일괄 승인'));
    await tester.pumpAndSettle();
    expect(submitted, {
      'changes:1': {'consignee_name': 'Alice corrected'},
      'changes:2': <String, dynamic>{},
    });
  });
}
