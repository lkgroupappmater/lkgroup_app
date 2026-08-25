// lib/models/quote_request.dart
import 'package:intl/intl.dart';

// 포장 상태 enum
enum PackagingStatus {
  packed, // 포장 완료
  unpacked, // 미포장
  partial, // 일부 포장
}

extension PackagingStatusExtension on PackagingStatus {
  String get label {
    switch (this) {
      case PackagingStatus.packed:
        return '포장 완료';
      case PackagingStatus.unpacked:
        return '미포장';
      case PackagingStatus.partial:
        return '일부 포장';
    }
  }
}

// 견적 요청 상태
enum QuoteStatus {
  pending, // 접수 대기
  reviewing, // 검토 중
  quoted, // 견적 발송
  confirmed, // 확정
  cancelled, // 취소
}

extension QuoteStatusExtension on QuoteStatus {
  String get label {
    switch (this) {
      case QuoteStatus.pending:
        return '접수 대기';
      case QuoteStatus.reviewing:
        return '검토 중';
      case QuoteStatus.quoted:
        return '견적 발송';
      case QuoteStatus.confirmed:
        return '확정';
      case QuoteStatus.cancelled:
        return '취소';
    }
  }
}

// 운송 수단 선택 (견적용)
enum QuoteTransportMode {
  sea,
  air,
  land,
  mixed,
  undecided, // 미정 (고객이 추천 요청)
}

extension QuoteTransportModeExtension on QuoteTransportMode {
  String get label {
    switch (this) {
      case QuoteTransportMode.sea:
        return '해상';
      case QuoteTransportMode.air:
        return '항공';
      case QuoteTransportMode.land:
        return '육로';
      case QuoteTransportMode.mixed:
        return '복합';
      case QuoteTransportMode.undecided:
        return '미정 (추천 요청)';
    }
  }
}

// 견적 요청 모델
class QuoteRequest {
  final String id;
  final String customerName;
  final String contactPhone;
  final String? contactEmail;
  final String origin;
  final String destination;
  final QuoteTransportMode transportMode;
  final DateTime? desiredShipDate;
  final String? cargoType; // 화물 종류
  final int? quantity; // 수량
  final double? totalWeightKg; // 총 중량 (kg)
  final double? lengthCm; // 가로 (cm)
  final double? widthCm; // 세로 (cm)
  final double? heightCm; // 높이 (cm)
  final PackagingStatus packagingStatus;
  final bool customsRequired;
  final bool insuranceRequired;
  final String? additionalNotes; // 추가 요청사항
  final QuoteStatus status;
  final DateTime createdAt;
  final String? assignedTo; // 담당자 ID (관리자 배정)

  const QuoteRequest({
    required this.id,
    required this.customerName,
    required this.contactPhone,
    this.contactEmail,
    required this.origin,
    required this.destination,
    required this.transportMode,
    this.desiredShipDate,
    this.cargoType,
    this.quantity,
    this.totalWeightKg,
    this.lengthCm,
    this.widthCm,
    this.heightCm,
    this.packagingStatus = PackagingStatus.unpacked,
    this.customsRequired = false,
    this.insuranceRequired = false,
    this.additionalNotes,
    this.status = QuoteStatus.pending,
    required this.createdAt,
    this.assignedTo,
  });

  // TODO: Supabase 연결 시 fromJson/toJson 사용
  factory QuoteRequest.fromJson(Map<String, dynamic> json) {
    return QuoteRequest(
      id: json['id'] as String,
      customerName: json['customer_name'] as String,
      contactPhone: json['contact_phone'] as String,
      contactEmail: json['contact_email'] as String?,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      transportMode: QuoteTransportMode.values.firstWhere(
        (m) => m.name == json['transport_mode'],
        orElse: () => QuoteTransportMode.undecided,
      ),
      desiredShipDate: json['desired_ship_date'] != null
          ? DateTime.parse(json['desired_ship_date'] as String)
          : null,
      cargoType: json['cargo_type'] as String?,
      quantity: json['quantity'] as int?,
      totalWeightKg: (json['total_weight_kg'] as num?)?.toDouble(),
      lengthCm: (json['length_cm'] as num?)?.toDouble(),
      widthCm: (json['width_cm'] as num?)?.toDouble(),
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      packagingStatus: PackagingStatus.values.firstWhere(
        (p) => p.name == json['packaging_status'],
        orElse: () => PackagingStatus.unpacked,
      ),
      customsRequired: json['customs_required'] as bool? ?? false,
      insuranceRequired: json['insurance_required'] as bool? ?? false,
      additionalNotes: json['additional_notes'] as String?,
      status: QuoteStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => QuoteStatus.pending,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      assignedTo: json['assigned_to'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_name': customerName,
        'contact_phone': contactPhone,
        'contact_email': contactEmail,
        'origin': origin,
        'destination': destination,
        'transport_mode': transportMode.name,
        'desired_ship_date': desiredShipDate?.toIso8601String(),
        'cargo_type': cargoType,
        'quantity': quantity,
        'total_weight_kg': totalWeightKg,
        'length_cm': lengthCm,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'packaging_status': packagingStatus.name,
        'customs_required': customsRequired,
        'insurance_required': insuranceRequired,
        'additional_notes': additionalNotes,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'assigned_to': assignedTo,
      };

  String get formattedCreatedAt =>
      DateFormat('yyyy-MM-dd HH:mm').format(createdAt);

  String get formattedDesiredShipDate {
    if (desiredShipDate == null) return '미정';
    return DateFormat('yyyy-MM-dd').format(desiredShipDate!);
  }

  // 부피 계산 (CBM)
  double? get volumeCbm {
    if (lengthCm == null || widthCm == null || heightCm == null) return null;
    return (lengthCm! * widthCm! * heightCm!) / 1000000;
  }
}
