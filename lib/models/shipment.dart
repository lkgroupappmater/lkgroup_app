// lib/models/shipment.dart
import 'package:intl/intl.dart';

// 운송 상태 enum - 타임라인 순서와 일치
enum ShipmentStatus {
  registered,      // 등록
  bookingConfirmed, // 예약 완료
  loadingComplete, // 선적 완료
  inTransit,       // 운송 중
  inCustoms,       // 통관 중
  delivered,       // 도착 완료
}

extension ShipmentStatusExtension on ShipmentStatus {
  String get label {
    switch (this) {
      case ShipmentStatus.registered:
        return '등록';
      case ShipmentStatus.bookingConfirmed:
        return '예약 완료';
      case ShipmentStatus.loadingComplete:
        return '선적 완료';
      case ShipmentStatus.inTransit:
        return '운송 중';
      case ShipmentStatus.inCustoms:
        return '통관 중';
      case ShipmentStatus.delivered:
        return '도착 완료';
    }
  }

  // 상태 인덱스 (타임라인 표시용)
  int get stepIndex => ShipmentStatus.values.indexOf(this);
}

// 운송 수단 enum
enum TransportMode {
  sea,   // 해상
  air,   // 항공
  land,  // 육로
  mixed, // 복합
}

extension TransportModeExtension on TransportMode {
  String get label {
    switch (this) {
      case TransportMode.sea:
        return '해상';
      case TransportMode.air:
        return '항공';
      case TransportMode.land:
        return '육로';
      case TransportMode.mixed:
        return '복합';
    }
  }

  String get icon {
    switch (this) {
      case TransportMode.sea:
        return '🚢';
      case TransportMode.air:
        return '✈️';
      case TransportMode.land:
        return '🚛';
      case TransportMode.mixed:
        return '🔄';
    }
  }
}

// 운송 노선 enum
// TODO: 실제 운영 노선에 따라 확장
enum TransportRoute {
  krLaosSeaExport,    // 한국 → 라오스 (해상) ← 현재 기본 노선
  krLaosAirExport,    // 한국 → 라오스 (항공) ← 향후 추가
  laosKrAirImport,    // 라오스 → 한국 (항공) ← 향후 추가
  laosThailandLand,   // 라오스 → 태국 (육로) ← 향후 추가
}

extension TransportRouteExtension on TransportRoute {
  String get label {
    switch (this) {
      case TransportRoute.krLaosSeaExport:
        return '한국 → 라오스 (해상)';
      case TransportRoute.krLaosAirExport:
        return '한국 → 라오스 (항공)';
      case TransportRoute.laosKrAirImport:
        return '라오스 → 한국 (항공)';
      case TransportRoute.laosThailandLand:
        return '라오스 → 태국 (육로)';
    }
  }

  TransportMode get mode {
    switch (this) {
      case TransportRoute.krLaosSeaExport:
        return TransportMode.sea;
      case TransportRoute.krLaosAirExport:
      case TransportRoute.laosKrAirImport:
        return TransportMode.air;
      case TransportRoute.laosThailandLand:
        return TransportMode.land;
    }
  }

  String get originCountry {
    switch (this) {
      case TransportRoute.krLaosSeaExport:
      case TransportRoute.krLaosAirExport:
        return '대한민국';
      case TransportRoute.laosKrAirImport:
      case TransportRoute.laosThailandLand:
        return '라오스';
    }
  }

  String get destinationCountry {
    switch (this) {
      case TransportRoute.krLaosSeaExport:
      case TransportRoute.krLaosAirExport:
        return '라오스';
      case TransportRoute.laosKrAirImport:
        return '대한민국';
      case TransportRoute.laosThailandLand:
        return '태국';
    }
  }
}

// 화물 모델
class Shipment {
  final String id;
  final String trackingNumber;   // 화물 번호 (ex. IC-2026-00125)
  final String customerName;
  final String customerId;
  final String origin;           // 출발지 항구/공항/도시
  final String destination;      // 도착지 항구/공항/도시
  final TransportRoute route;
  final ShipmentStatus status;
  final DateTime createdAt;
  final DateTime? estimatedArrival;
  final DateTime? actualArrival;
  final double? weightKg;
  final double? volumeCbm;      // 부피 (CBM)
  final String? containerNumber;
  final String? vesselName;      // 선박명
  final String? flightNumber;    // 항공편
  final String? notes;
  final List<ShipmentEvent> events; // 상태 변경 이력
  final bool customsRequired;
  final bool insuranceRequired;
  final String? cargoType;

  const Shipment({
    required this.id,
    required this.trackingNumber,
    required this.customerName,
    required this.customerId,
    required this.origin,
    required this.destination,
    required this.route,
    required this.status,
    required this.createdAt,
    this.estimatedArrival,
    this.actualArrival,
    this.weightKg,
    this.volumeCbm,
    this.containerNumber,
    this.vesselName,
    this.flightNumber,
    this.notes,
    this.events = const [],
    this.customsRequired = false,
    this.insuranceRequired = false,
    this.cargoType,
  });

  // TODO: Supabase/PostgreSQL 연결 시 fromJson/toJson 사용
  factory Shipment.fromJson(Map<String, dynamic> json) {
    return Shipment(
      id: json['id'] as String,
      trackingNumber: json['tracking_number'] as String,
      customerName: json['customer_name'] as String,
      customerId: json['customer_id'] as String,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      route: TransportRoute.values.firstWhere(
            (r) => r.name == json['route'],
        orElse: () => TransportRoute.krLaosSeaExport,
      ),
      status: ShipmentStatus.values.firstWhere(
            (s) => s.name == json['status'],
        orElse: () => ShipmentStatus.registered,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      estimatedArrival: json['estimated_arrival'] != null
          ? DateTime.parse(json['estimated_arrival'] as String)
          : null,
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      volumeCbm: (json['volume_cbm'] as num?)?.toDouble(),
      containerNumber: json['container_number'] as String?,
      vesselName: json['vessel_name'] as String?,
      notes: json['notes'] as String?,
      customsRequired: json['customs_required'] as bool? ?? false,
      insuranceRequired: json['insurance_required'] as bool? ?? false,
      cargoType: json['cargo_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tracking_number': trackingNumber,
    'customer_name': customerName,
    'customer_id': customerId,
    'origin': origin,
    'destination': destination,
    'route': route.name,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'estimated_arrival': estimatedArrival?.toIso8601String(),
    'weight_kg': weightKg,
    'volume_cbm': volumeCbm,
    'container_number': containerNumber,
    'vessel_name': vesselName,
    'notes': notes,
    'customs_required': customsRequired,
    'insurance_required': insuranceRequired,
    'cargo_type': cargoType,
  };

  String get formattedEstimatedArrival {
    if (estimatedArrival == null) return '-';
    return DateFormat('yyyy-MM-dd').format(estimatedArrival!);
  }

  String get formattedCreatedAt =>
      DateFormat('yyyy-MM-dd').format(createdAt);
}

// 화물 상태 변경 이벤트 (타임라인용)
class ShipmentEvent {
  final String id;
  final ShipmentStatus status;
  final DateTime timestamp;
  final String? location;
  final String? description;

  const ShipmentEvent({
    required this.id,
    required this.status,
    required this.timestamp,
    this.location,
    this.description,
  });

  factory ShipmentEvent.fromJson(Map<String, dynamic> json) {
    return ShipmentEvent(
      id: json['id'] as String,
      status: ShipmentStatus.values.firstWhere(
            (s) => s.name == json['status'],
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      location: json['location'] as String?,
      description: json['description'] as String?,
    );
  }

  String get formattedTimestamp =>
      DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
}



