// lib/services/shipment_service.dart
import '../models/shipment.dart';
import '../data/mock_data.dart';

// 화물 서비스
// TODO: Supabase REST API / Realtime 구독으로 교체
class ShipmentService {
  // 싱글톤 패턴
  static final ShipmentService _instance = ShipmentService._internal();
  factory ShipmentService() => _instance;
  ShipmentService._internal();

  // 전체 화물 목록 조회
  // TODO: Supabase: supabase.from('shipments').select('*, events(*)')
  Future<List<Shipment>> getAllShipments() async {
    await Future.delayed(const Duration(milliseconds: 300)); // mock 네트워크 지연
    return MockShipments.all;
  }

  // 화물 번호로 단건 조회
  // TODO: Supabase: .eq('tracking_number', trackingNumber).single()
  Future<Shipment?> findByTrackingNumber(String trackingNumber) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return MockShipments.findByTracking(trackingNumber);
  }

  // 고객 ID로 화물 조회
  // TODO: Supabase: .eq('customer_id', customerId)
  Future<List<Shipment>> getShipmentsForCustomer(String customerId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return MockShipments.forCustomer(customerId);
  }

  // 키워드 검색 (화물 번호 / 고객명 / 출발지 / 도착지)
  Future<List<Shipment>> searchShipments(String query) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (query.trim().isEmpty) return MockShipments.all;
    final q = query.trim().toLowerCase();
    return MockShipments.all.where((s) {
      return s.trackingNumber.toLowerCase().contains(q) ||
          s.customerName.toLowerCase().contains(q) ||
          s.origin.toLowerCase().contains(q) ||
          s.destination.toLowerCase().contains(q) ||
          (s.cargoType?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  // 상태별 필터
  Future<List<Shipment>> getShipmentsByStatus(ShipmentStatus status) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return MockShipments.all.where((s) => s.status == status).toList();
  }

  // TODO: 화물 상태 업데이트 (관리자용)
  // Supabase: .update({'status': newStatus.name}).eq('id', id)
  Future<bool> updateStatus(String shipmentId, ShipmentStatus newStatus) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // mock: 실제로는 UI 갱신을 위해 상태 관리(Provider/Riverpod) 필요
    return true;
  }

// TODO: 엑셀 업로드 후 화물 일괄 등록
// Future<int> bulkCreateFromExcel(List<Map<String, dynamic>> rows) async {...}
}


