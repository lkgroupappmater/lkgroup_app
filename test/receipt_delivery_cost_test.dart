import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/receipt_delivery_cost.dart';
import 'package:lkgroup_app/services/receipt_extra_cost_service.dart';

void main() {
  test('prepaid notes recognize both spellings and ordinary delivery has no fee row', () {
    for (final marker in ['선결제', '선결재', '선불']) {
      expect(
        ReceiptDeliveryCost.prepaidType([
          {'special_note_auto': '지방 배송 ($marker)'},
        ]),
        'province',
      );
      expect(
        ReceiptDeliveryCost.prepaidType([
          {'special_note_auto': '시내배송($marker)'},
        ]),
        'city',
      );
    }
    expect(
      ReceiptDeliveryCost.prepaidType([
        {'special_note_auto': '지방배송'},
      ]),
      isNull,
    );
    expect(
      ReceiptDeliveryCost.prepaidType(
        [
          {'special_note_auto': '시내배송 (선결제)'},
        ],
        profileType: 'province',
        profilePrepaid: false,
      ),
      isNull,
    );
  });
  test('suggested delivery is blank priced, undiscounted, and absent for non-prepaid receipts', () {
    final pending = ReceiptDeliveryCost.forStatement([], 'province').single;
    expect(pending.name, '지방배송');
    expect(pending.pending, isTrue);
    expect(pending.discountApplies, isFalse);
    expect(pending.amountUsd, 0);
    expect(ReceiptDeliveryCost.forStatement([], null), isEmpty);
  });
  test('renamed, legacy and explicit zero costs are not duplicated', () {
    for (final cost in [
      const ExtraCostItem(
        id: 1,
        name: '업체 운임',
        amountUsd: 0,
        deliveryType: 'city',
      ),
      const ExtraCostItem(id: 2, name: '시내배송', amountUsd: 25),
    ]) {
      final costs = ReceiptDeliveryCost.forStatement([cost], 'city');
      expect(costs.length, 1);
      expect(costs.single.pending, isFalse);
    }
    final saved = ExtraCostItem.fromMap({
      'id': 1,
      'cost_name': '업체 운임',
      'amount_usd': 30,
      'delivery_type': 'city',
      'discount_applies': true,
    });
    expect(saved.deliveryType, 'city');
    expect(saved.discountApplies, isTrue);
  });
}
