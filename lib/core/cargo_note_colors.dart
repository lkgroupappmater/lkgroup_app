import 'package:flutter/material.dart';

/// The four effective workbook fill keys; never changes the stored remark.
class CargoNoteColors {
  CargoNoteColors._();
  static const defaults = <String, String>{
    'province': 'FFC000', 'province_prepaid': '9DC3E6',
    'city': 'A9D18E', 'city_prepaid': 'D6B18A',
  };
  static String kind(Map<String, dynamic> row) {
    for (final key in ['special_note_auto', 'special_note', 'notes', 'note']) {
      final text = '${row[key] ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_\-()（）:：]+'), '');
      final m = RegExp(r'(지방배송|시내배송|시내배소|provincialdelivery|provincedelivery|citydelivery)(선결제|선결재|선불|prepaid|payinadvance)?').firstMatch(text);
      if (m != null) return '${['시내배송', '시내배소', 'citydelivery'].contains(m[1]) ? 'city' : 'province'}${m[2] == null ? '' : '_prepaid'}';
    }
    return '';
  }
  static Map<String, String> palette([Map base = const {}, Map voyage = const {}]) {
    final result = {...defaults};
    for (final source in [base, voyage]) {
      for (final key in defaults.keys) {
        var value = '${source[key] ?? ''}'.trim().replaceFirst(RegExp(r'^#'), '').toUpperCase();
        if (value.length == 8 && value.startsWith('FF')) value = value.substring(2);
        if (RegExp(r'^[A-F0-9]{6}$').hasMatch(value)) result[key] = value;
      }
    }
    return result;
  }
  static Color? color(Map<String, dynamic> row, [Map colors = const {}]) {
    final key = kind(row); if (key.isEmpty) return null;
    return Color(int.parse('FF${palette(colors)[key]}', radix: 16));
  }
  static Color ink(Color color) => color.computeLuminance() > .179 ? const Color(0xFF111827) : Colors.white;
}
