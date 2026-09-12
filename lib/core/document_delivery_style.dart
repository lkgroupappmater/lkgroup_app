import 'package:flutter/material.dart';

/// Existing workbook colors for the address actually printed on the document.
class DocumentDeliveryStyle {
  DocumentDeliveryStyle._();

  static const province = Color(0xFFFFC000);
  static const city = Color(0xFF92D050);
  static const provincePrepaid = Color(0xFF5B9BD5);
  static const cityPrepaid = Color(0xFFD6B18A);

  static Color? fromProfile(String type, {required bool prepaid}) {
    if (type == 'province') return prepaid ? provincePrepaid : province;
    if (type == 'city') return prepaid ? cityPrepaid : city;
    return null;
  }

  /// Legacy notes can contain spaces, alternate spelling, or English markers.
  /// Only a payment marker next to the delivery token affects its color.
  static Color? fromNotes(Iterable<String> notes) {
    final pattern = RegExp(
      r'(지방배송|시내배송|provincialdelivery|provincedelivery|citydelivery)'
      r'(선결제|선결재|선불|prepaid|payinadvance)?',
    );
    for (final note in notes) {
      final normalized = note.toLowerCase().replaceAll(
        RegExp(r'[\s_\-()（）:：]+'), '',
      );
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      final type = match[1] == '시내배송' || match[1] == 'citydelivery'
          ? 'city' : 'province';
      return fromProfile(type, prepaid: match[2] != null);
    }
    return null;
  }
}
