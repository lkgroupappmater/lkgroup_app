// lib/widgets/status_timeline.dart

import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// A vertical timeline that highlights the current step.
class StatusTimeline extends StatelessWidget {
  final List<String> statuses;
  final int currentIndex;

  const StatusTimeline({
    super.key,
    required this.statuses,
    this.currentIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(statuses.length, (i) {
        final isCompleted = i < currentIndex;
        final isCurrent   = i == currentIndex;
        final isLast      = i == statuses.length - 1;

        final dotColor = isCompleted
            ? AppColors.success
            : isCurrent
            ? AppColors.tealAccent
            : AppColors.textSecondary.withOpacity(0.35);

        final labelStyle = TextStyle(
          fontSize: 13,
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
          color: isCurrent
              ? AppColors.textPrimary
              : isCompleted
              ? AppColors.textSecondary
              : AppColors.textSecondary.withOpacity(0.6),
        );

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: isCurrent
                            ? Border.all(
                            color: AppColors.tealAccent, width: 2)
                            : null,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isCompleted
                              ? AppColors.success.withOpacity(0.4)
                              : AppColors.textSecondary.withOpacity(0.2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: isLast ? 0 : 20, top: 0),
                  child: Text(statuses[i], style: labelStyle),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// A compact coloured badge for shipment/order status labels.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const StatusBadge({
    super.key,
    required this.label,
    this.color,
  });

  Color _defaultColor() {
    final l = label.toLowerCase();
    if (l.contains('delivered') || l.contains('complete')) {
      return AppColors.success;
    } else if (l.contains('progress') || l.contains('transit')) {
      return AppColors.inProgress;
    } else if (l.contains('pending') || l.contains('wait')) {
      return AppColors.warning;
    } else if (l.contains('cancel') || l.contains('fail')) {
      return AppColors.error;
    }
    return AppColors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    final bg = color ?? _defaultColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: bg,
        ),
      ),
    );
  }
}
