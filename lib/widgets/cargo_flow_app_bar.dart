// lib/widgets/cargo_flow_app_bar.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import 'company_logo.dart';

/// Shared header. Use once from AppShell; body screens must not add another AppBar.
class CargoFlowAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final AppLanguage selectedLanguage;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback? onNotificationTap;
  final bool showHomeActions;
  final int notificationCount;

  const CargoFlowAppBar({
    super.key,
    required this.title,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    this.onNotificationTap,
    this.showHomeActions = false,
    this.notificationCount = 0,
  });

  // Includes the device status-bar inset; no second title row is added.
  static const double _barHeight = 115;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      height: _barHeight,
      padding: EdgeInsets.only(top: top),
      color: AppColors.primary,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: const CompanyLogo(width: 120, height: 60, white: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 118),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 언어 선택은 모든 메뉴에서 표시하고, 알림은 홈에서만 표시합니다.
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHomeActions)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: '알림',
                        onPressed:
                            onNotificationTap ?? () => _showNotifications(context),
                        icon: const Icon(Icons.notifications_outlined,
                            color: AppColors.white, size: 31),
                      ),
                      if (notificationCount > 0)
                        Positioned(
                          right: 5,
                          top: 5,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              notificationCount > 9 ? '9+' : '$notificationCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                _LanguageFlagButton(
                  selectedLanguage: selectedLanguage,
                  onChanged: onLanguageChanged,
                ),
                const SizedBox(width: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.get(selectedLanguage, 'notifications')),
        content: Text(AppStrings.get(selectedLanguage, 'no_notifications')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.get(selectedLanguage, 'close')),
          ),
        ],
      ),
    );
  }
}

class _LanguageFlagButton extends StatelessWidget {
  final AppLanguage selectedLanguage;
  final ValueChanged<AppLanguage> onChanged;

  const _LanguageFlagButton({
    required this.selectedLanguage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppLanguage>(
      tooltip: 'Language / 언어',
      offset: const Offset(0, 52),
      color: AppColors.primary,
      onSelected: onChanged,
      itemBuilder: (_) => AppLanguage.values.map((language) {
        final selected = language == selectedLanguage;
        return PopupMenuItem<AppLanguage>(
          value: language,
          child: Row(
            children: [
              Text(language.flag, style: const TextStyle(fontSize: 23)),
              const SizedBox(width: 10),
              Text(
                language.label,
                style: TextStyle(
                  color: selected ? AppColors.tealAccent : AppColors.white,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                const Icon(Icons.check, color: AppColors.tealAccent, size: 18),
              ],
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child:
            Text(selectedLanguage.flag, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}
