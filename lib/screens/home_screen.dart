// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class HomeScreen extends StatelessWidget {
  // Flexible constructor — accepts whatever old call-sites pass.
  final dynamic currentUser;
  final int selectedIndex;
  final String title;
  final Widget? body;

  const HomeScreen({
    super.key,
    this.currentUser,
    this.selectedIndex = 0,
    this.title = 'LK Group',
    this.body,
  });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: _buildAppBar(context),
      body: body ?? _DashboardBody(title: title),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.navyPrimary,
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.tealAccent,
              borderRadius: BorderRadius.circular(6),
            ),
            child:
                const Icon(Icons.local_shipping, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white70),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No new notifications')),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  final String title;

  const _DashboardBody({required this.title});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero / greeting ───────────────────────────────────────────────
          _HeroCard(title: title),
          const SizedBox(height: 24),

          // ── Quick stats ───────────────────────────────────────────────────
          const Text(
            'Overview',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                  child: _StatCard(
                      label: 'Active',
                      value: '12',
                      icon: Icons.pending_actions,
                      color: AppColors.inProgress)),
              SizedBox(width: 12),
              Expanded(
                  child: _StatCard(
                      label: 'In Transit',
                      value: '5',
                      icon: Icons.local_shipping_outlined,
                      color: AppColors.tealAccent)),
              SizedBox(width: 12),
              Expanded(
                  child: _StatCard(
                      label: 'Delivered',
                      value: '48',
                      icon: Icons.check_circle_outline,
                      color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 24),

          // ── Quick actions ─────────────────────────────────────────────────
          const Text(
            'Quick Actions',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: const [
              _ActionCard(
                icon: Icons.search,
                label: 'Track Shipment',
                color: AppColors.tealAccent,
              ),
              _ActionCard(
                icon: Icons.add_box_outlined,
                label: 'New Booking',
                color: AppColors.inProgress,
              ),
              _ActionCard(
                icon: Icons.description_outlined,
                label: 'Documents',
                color: AppColors.warning,
              ),
              _ActionCard(
                icon: Icons.support_agent_outlined,
                label: 'Support',
                color: AppColors.navyPrimary,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Recent shipments ──────────────────────────────────────────────
          const Text(
            'Recent Shipments',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          const _ShipmentListItem(
            no: 'IC-2026-00125',
            route: 'SHA → KUL',
            status: 'In Transit',
            statusColor: AppColors.inProgress,
          ),
          const SizedBox(height: 10),
          const _ShipmentListItem(
            no: 'IC-2026-00118',
            route: 'PVG → SIN',
            status: 'Customs Hold',
            statusColor: AppColors.warning,
          ),
          const SizedBox(height: 10),
          const _ShipmentListItem(
            no: 'IC-2026-00103',
            route: 'HKG → JHB',
            status: 'Delivered',
            statusColor: AppColors.success,
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final String title;

  const _HeroCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navyPrimary, Color(0xFF1B3A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyPrimary.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome back 👋',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'CargoFlow — Logistics at your fingertips.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label tapped')),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ShipmentListItem extends StatelessWidget {
  final String no;
  final String route;
  final String status;
  final Color statusColor;

  const _ShipmentListItem({
    required this.no,
    required this.route,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.navyPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_shipping_outlined,
                color: AppColors.navyPrimary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(no,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(route,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Text(status,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor)),
          ),
        ],
      ),
    );
  }
}
