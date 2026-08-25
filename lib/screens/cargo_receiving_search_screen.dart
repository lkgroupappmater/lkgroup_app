// lib/screens/cargo_receiving_search_screen.dart

import 'package:flutter/material.dart';
import '../models/cargo_receiving.dart';
import '../data/dashboard_mock_data.dart';

class CargoReceivingSearchScreen extends StatefulWidget {
  const CargoReceivingSearchScreen({super.key});

  @override
  State<CargoReceivingSearchScreen> createState() =>
      _CargoReceivingSearchScreenState();
}

class _CargoReceivingSearchScreenState
    extends State<CargoReceivingSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CargoReceiving> get _results {
    if (_query.trim().isEmpty) return DashboardMockData.cargoReceivings;
    final q = _query.trim().toLowerCase();
    return DashboardMockData.cargoReceivings.where((c) {
      return c.receiptNo.toLowerCase().contains(q) ||
          c.invoiceNo.toLowerCase().contains(q) ||
          c.consigneeName.toLowerCase().contains(q) ||
          c.contact.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A3A5C),
        title: const Text('화물 입고 조회', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '입고번호 · 인보이스번호 · 수하인 · 연락처',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '검색 결과 ${_results.length}건',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('검색 결과가 없습니다.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _results.length,
                    itemBuilder: (context, index) =>
                        _CargoCard(cargo: _results[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cargo Card
// ---------------------------------------------------------------------------
class _CargoCard extends StatelessWidget {
  const _CargoCard({required this.cargo});
  final CargoReceiving cargo;

  Color get _statusColor {
    switch (cargo.status) {
      case CargoReceivingStatus.received:
        return const Color(0xFF1A7AC7);
      case CargoReceivingStatus.inspecting:
        return const Color(0xFFE67E22);
      case CargoReceivingStatus.stored:
        return const Color(0xFF4CAF50);
      case CargoReceivingStatus.readyToShip:
        return const Color(0xFF9C27B0);
      case CargoReceivingStatus.shipped:
        return const Color(0xFF607D8B);
      case CargoReceivingStatus.returned:
        return const Color(0xFFF44336);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cargo.receiptNo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1A3A5C),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    cargo.statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: _statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF2F7)),
            const SizedBox(height: 8),
            _InfoRow(label: '인보이스번호', value: cargo.invoiceNo),
            _InfoRow(label: '수하인', value: cargo.consigneeName),
            _InfoRow(label: '연락처', value: cargo.contact),
            _InfoRow(label: '입고일', value: cargo.receivedDate),
            _InfoRow(label: '보관 위치', value: cargo.storageLocation),
            if (cargo.shipmentNo.isNotEmpty)
              _InfoRow(label: '선적 번호', value: cargo.shipmentNo),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF37474F)),
            ),
          ),
        ],
      ),
    );
  }
}
