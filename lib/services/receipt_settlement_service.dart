import 'freight_service.dart';

class ReceiptSettlement {
  const ReceiptSettlement({
    required this.receiptNumber,
    required this.customerName,
    required this.phone,
    required this.rows,
    required this.freight,
    required this.totalQuantity,
  });

  final String receiptNumber;
  final String customerName;
  final String phone;
  final List<Map<String, dynamic>> rows;
  final FreightCalculation freight;
  final int totalQuantity;

  double get grossUsd => freight.grossTotalUsd;
  double get discountUsd => freight.discountTotalUsd;
  double get netUsd => freight.totalUsd;
}

class VoyageSettlement {
  const VoyageSettlement({
    required this.receipts,
    required this.totalQuantity,
    required this.grossUsd,
    required this.discountUsd,
    required this.netUsd,
    required this.discountByGroup,
  });

  final List<ReceiptSettlement> receipts;
  final int totalQuantity;
  final double grossUsd;
  final double discountUsd;
  final double netUsd;
  final Map<String, double> discountByGroup;
}

class ReceiptSettlementService {
  ReceiptSettlementService._();
  static final instance = ReceiptSettlementService._();

  int _qty(dynamic value) {
    final n = num.tryParse('${value ?? ''}'.replaceAll(',', '').trim());
    return (n ?? 1).round().clamp(1, 999999).toInt();
  }

  String _receipt(Map<String, dynamic> row) {
    final value = '${row['receipt_number'] ?? ''}'.trim();
    return value.isEmpty ? '미배정' : value;
  }

  int _receiptSortValue(String value) {
    if (value.toUpperCase().contains('XX')) return 1 << 30;
    final match = RegExp(r'(\d+)(?!.*\d)').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '') ?? ((1 << 30) - 1);
  }

  Future<VoyageSettlement> calculate(
    List<Map<String, dynamic>> rows,
  ) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped.putIfAbsent(_receipt(row), () => []).add(row);
    }

    final receipts = <ReceiptSettlement>[];
    final discountByGroup = <String, double>{};

    for (final entry in grouped.entries) {
      final freight = await FreightService.instance.calculate(entry.value);
      final first = entry.value.first;
      final quantity = entry.value.fold<int>(
        0,
        (sum, row) => sum + _qty(row['quantity']),
      );

      for (final group in freight.discountByGroup.entries) {
        discountByGroup[group.key] =
            (discountByGroup[group.key] ?? 0) + group.value;
      }

      receipts.add(
        ReceiptSettlement(
          receiptNumber: entry.key,
          customerName: '${first['consignee_name'] ?? ''}'.trim(),
          phone: '${first['consignee_phone'] ?? ''}'.trim(),
          rows: List<Map<String, dynamic>>.unmodifiable(entry.value),
          freight: freight,
          totalQuantity: quantity,
        ),
      );
    }

    receipts.sort((a, b) {
      final av = _receiptSortValue(a.receiptNumber);
      final bv = _receiptSortValue(b.receiptNumber);
      final c = av.compareTo(bv);
      return c != 0 ? c : a.receiptNumber.compareTo(b.receiptNumber);
    });

    return VoyageSettlement(
      receipts: List<ReceiptSettlement>.unmodifiable(receipts),
      totalQuantity:
          receipts.fold(0, (sum, receipt) => sum + receipt.totalQuantity),
      grossUsd:
          receipts.fold(0, (sum, receipt) => sum + receipt.grossUsd),
      discountUsd:
          receipts.fold(0, (sum, receipt) => sum + receipt.discountUsd),
      netUsd:
          receipts.fold(0, (sum, receipt) => sum + receipt.netUsd),
      discountByGroup: Map<String, double>.unmodifiable(discountByGroup),
    );
  }
}
