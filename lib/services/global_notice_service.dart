import 'package:flutter/material.dart';

class GlobalNoticeService {
  GlobalNoticeService._();
  static final GlobalNoticeService instance = GlobalNoticeService._();
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  void show(String message, {bool error = false}) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m..hideCurrentSnackBar()..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.redAccent : null,
      duration: const Duration(seconds: 5),
    ));
  }
}
