import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/domestic_tracking_text.dart';
import '../models/app_user.dart';
import '../services/shared_ui_text_service.dart';

enum TrackingChoice { cargo, domestic }

Future<TrackingChoice?> showTrackingChoiceSheet(
  BuildContext context, AppLanguage language, UserRole? role,
) => showModalBottomSheet<TrackingChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => TrackingChoiceSheet(language: language, role: role),
);

class TrackingChoiceSheet extends StatelessWidget {
  const TrackingChoiceSheet({super.key, required this.language, this.role});
  final AppLanguage language;
  final UserRole? role;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: AnimatedBuilder(
      animation: SharedUiTextService.instance,
      builder: (context, _) => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(AppStrings.get(language, 'tracking')),
            onTap: () => Navigator.pop(context, TrackingChoice.cargo),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(domesticTitle(language, role)),
            onTap: () => Navigator.pop(context, TrackingChoice.domestic),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    ),
  );
}
