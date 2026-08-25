// lib/screens/shipment_detail_screen.dart

import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../widgets/status_timeline.dart';

class ShipmentDetailScreen extends StatelessWidget {
  final String shipmentNo;

  const ShipmentDetailScreen({
    super.key,
    this.shipmentNo = 'IC-2026-00125',
  });

  // ── Static demo data ──────────────────────────────────────────────────────

  static const List<String> _timelineStatuses = [
    'Order Placed',
    'Picked Up',
    'In Transit',
    'Customs Clearance',
    'Out for Delivery',
    'Delivered',
  ];

  static const int _currentStep = 2; // In Transit

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: Colors.white,
        title: Text(
          shipmentNo,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status badge row ────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Shipment Status',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const StatusBadge(label: 'In Transit'),
              ],
            ),

            const SizedBox(height: 20),

            // ── Summary card ────────────────────────────────────────────────
            _SummaryCard(shipmentNo: shipmentNo),

            const SizedBox(height: 24),

            // ── Timeline card ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tracking Timeline',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 20),
                  StatusTimeline(
                    statuses: _timelineStatuses,
                    currentIndex: _currentStep,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Route card ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Route Information',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const Divider(height: 24),
                  _routeRow(
                    icon: Icons.flight_takeoff,
                    color: AppColors.tealAccent,
                    label: 'Origin',
                    value: 'Shanghai, China (SHA)',
                  ),
                  const SizedBox(height: 12),
                  _routeRow(
                    icon: Icons.flight_land,
                    color: AppColors.inProgress,
                    label: 'Destination',
                    value: 'Kuala Lumpur, Malaysia (KUL)',
                  ),
                  const SizedBox(height: 12),
                  _routeRow(
                    icon: Icons.local_shipping_outlined,
                    color: AppColors.warning,
                    label: 'Carrier',
                    value: 'LK Express Freight',
                  ),
                  const SizedBox(height: 12),
                  _routeRow(
                    icon: Icons.calendar_today_outlined,
                    color: AppColors.success,
                    label: 'ETA',
                    value: '28 Jul 2026',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Cargo details card ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cargo Details',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      _cargoChip(Icons.inventory_2_outlined, '3 Packages'),
                      const SizedBox(width: 12),
                      _cargoChip(Icons.scale_outlined, '142 kg'),
                      const SizedBox(width: 12),
                      _cargoChip(Icons.straighten_outlined, '2.4 CBM'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Electronics — Fragile',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );

  Widget _routeRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cargoChip(IconData icon, String text) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.tealAccent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final String shipmentNo;

  const _SummaryCard({required this.shipmentNo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navyPrimary, Color(0xFF1B3A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyPrimary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping,
                  color: AppColors.tealAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                shipmentNo,
                style: const TextStyle(
                    color: AppColors.tealAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'International Cargo',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _pill('Sea Freight'),
              const SizedBox(width: 8),
              _pill('FCL 20\''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      );
}
