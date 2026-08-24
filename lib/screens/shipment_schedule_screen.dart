// lib/screens/shipment_schedule_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Full schedule list screen (opened from home "목록 자세히 보기").
/// Has its own Scaffold + AppBar since it's pushed via Navigator.
class ShipmentScheduleScreen extends StatelessWidget {
  const ShipmentScheduleScreen({super.key});

  static const List<Map<String, dynamic>> _schedules = [
    {
      'id': 'SCH-001',
      'route': '한국->라오스 해상',
      'status': '운송 중',
      'eta': '2025-07-18',
      'boxes': 12,
      'departure': '부산항',
      'destination': '비엔티안',
    },
    {
      'id': 'SCH-002',
      'route': '한국->라오스 항공',
      'status': '입고 완료',
      'eta': '2025-07-10',
      'boxes': 5,
      'departure': '인천공항',
      'destination': '왓따이공항',
    },
    {
      'id': 'SCH-003',
      'route': '라오스->태국 육로',
      'status': '통관 중',
      'eta': '2025-07-12',
      'boxes': 8,
      'departure': '비엔티안',
      'destination': '방콕',
    },
    {
      'id': 'SCH-004',
      'route': '라오스->베트남 육로',
      'status': '출발 예정',
      'eta': '2025-07-20',
      'boxes': 15,
      'departure': '비엔티안',
      'destination': '하노이',
    },
    {
      'id': 'SCH-005',
      'route': '라오스->중국 육로',
      'status': '운송 중',
      'eta': '2025-07-22',
      'boxes': 20,
      'departure': '루앙프라방',
      'destination': '쿤밍',
    },
  ];

  Color _statusColor(String s) {
    if (s.contains('운송')) return AppColors.inProgress;
    if (s.contains('완료')) return AppColors.success;
    if (s.contains('통관')) return AppColors.tagOrange;
    if (s.contains('예정')) return AppColors.tagBlue;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: AppColors.white,
        title: const Text('운송 스케줄 목록',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _schedules.length,
        itemBuilder: (context, i) {
          final s = _schedules[i];
          final status = s['status'] as String;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s['route'] as String,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(status,
                            style: TextStyle(
                                fontSize: 12,
                                color: _statusColor(status),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 8),
                  _InfoRow('스케줄 ID', s['id'] as String),
                  _InfoRow('출발지', s['departure'] as String),
                  _InfoRow('도착지', s['destination'] as String),
                  _InfoRow('박스 수량', '${s['boxes']}개'),
                  _InfoRow('도착 예정일', s['eta'] as String),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
