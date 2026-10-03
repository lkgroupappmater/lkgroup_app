import 'package:flutter/material.dart';
import '../core/app_language.dart';
import 'support_screen.dart';

class QuoteRequestManagementScreen extends StatelessWidget {
  const QuoteRequestManagementScreen(
      {super.key, this.language = AppLanguage.korean});
  final AppLanguage language;
  @override
  Widget build(BuildContext context) =>
      SupportInboxScreen(manager: true, language: language);
}
