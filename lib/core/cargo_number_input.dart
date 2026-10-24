import 'package:flutter/services.dart';
class CargoNumberInput {
  static String complete(String value, String prefix) {
    final raw=value.trim(); if(raw.isEmpty || prefix.isEmpty) return raw;
    if(raw.toUpperCase().startsWith(prefix.toUpperCase())) return prefix+raw.substring(prefix.length);
    return RegExp(r'^\d').hasMatch(raw) ? '$prefix$raw' : raw;
  }
  static TextInputFormatter formatter(String prefix) => TextInputFormatter.withFunction((oldValue,newValue) {
    if(prefix.isEmpty || !newValue.text.toUpperCase().startsWith(prefix.toUpperCase())) return newValue;
    final text=newValue.text.substring(prefix.length);
    return TextEditingValue(text:text,selection:TextSelection.collapsed(offset:(newValue.selection.extentOffset-prefix.length).clamp(0,text.length).toInt()));
  });
}
