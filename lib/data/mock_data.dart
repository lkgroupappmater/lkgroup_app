// lib/data/mock_data.dart
import '../models/app_user.dart';
import '../models/shipment.dart';
import '../models/quote_request.dart';

// ============================================================
// Mock 사용자 데이터
// TODO: Supabase Auth로 교체 시 이 목록 삭제
// ============================================================
class MockUsers {
  static const List<AppUser> all = [
    AppUser(
      id: 'guest',
      displayName: '게스트',
      role: UserRole.guest,
    ),
    AppUser(
      id: 'member-001',
      displayName: '김민준',
      email: 'minjun.kim@example.com',
      phone: '010-1234-5678',
      role: UserRole.member,
    ),
    AppUser(
      id: 'partner-001',
      displayName: '이서연',
      email: 'seoyeon.lee@tradeco.com',
      phone: '010-9876-5432',
      role: UserRole.partner,
      companyName: '한라무역(주)',
    ),
    AppUser(
      id: 'admin-001',
      displayName: '박관리자',
      email: 'admin@cargoflow.kr',
      phone: '010-0000-1111',
      role: UserRole.admin,
      companyName: 'CargoFlow',
    ),
  ];

  static AppUser byRole(UserRole role) =>
      all.firstWhere((u) => u.role == role);
}

// ============================================================
// Mock 화물 데이터
// TODO: Supabase/PostgreSQL REST API로 교체
// ============================================================
class MockShipments {
  static final List<Shipment> all = [
    // ★ 기본 샘플 화물 (요구사항 4번)
    Shipment(
      id: 'ship-001',
      trackingNumber: 'IC-2026-00125',
      customerName: '한라무역(주)',
      customerId: 'partner-001',
      origin: '부산항 (KRPUS)',
      destination: '비엔티안 ICD (LAVTE)',
      route: TransportRoute.krLaosSeaExport,
      status: ShipmentStatus.inTransit,
      createdAt: DateTime(2026, 7, 15),
      estimatedArrival: DateTime(2026, 8, 25),
      weightKg: 3250.0,
      volumeCbm: 12.5,
      containerNumber: 'MSCU7412356',
      vesselName: 'MSC BUSAN EXPRESS',
      customsRequired: true,
      insuranceRequired: true,
      cargoType: '전자부품 및 기계류',
      events: [
        ShipmentEvent(
          id: 'evt-001-1',
          status: ShipmentStatus.registered,
          timestamp: DateTime(2026, 7, 15, 9, 0),
          location: '부산, 대한민국',
          description: '화물 등록 완료',
        ),
        ShipmentEvent(
          id: 'evt-001-2',
          status: ShipmentStatus.bookingConfirmed,
          timestamp: DateTime(2026, 7, 17, 14, 30),
          location: '부산항 (KRPUS)',
          description: '선박 예약 확정 - MSC BUSAN EXPRESS',
        ),
        ShipmentEvent(
          id: 'evt-001-3',
          status: ShipmentStatus.loadingComplete,
          timestamp: DateTime(2026, 7, 22, 8, 15),
          location: '부산항 (KRPUS)',
          description: '컨테이너 선적 완료 (MSCU7412356)',
        ),
        ShipmentEvent(
          id: 'evt-001-4',
          status: ShipmentStatus.inTransit,
          timestamp: DateTime(2026, 7, 23, 6, 0),
          location: '부산항 출항',
          description: '출항 완료 → 태국 렘차방항 경유',
        ),
      ],
    ),

    Shipment(
      id: 'ship-002',
      trackingNumber: 'IC-2026-00118',
      customerName: '김민준',
      customerId: 'member-001',
      origin: '인천항 (KRICN)',
      destination: '비엔티안 ICD (LAVTE)',
      route: TransportRoute.krLaosSeaExport,
      status: ShipmentStatus.delivered,
      createdAt: DateTime(2026, 6, 1),
      estimatedArrival: DateTime(2026, 7, 10),
      actualArrival: DateTime(2026, 7, 9),
      weightKg: 850.0,
      volumeCbm: 4.2,
      containerNumber: 'HLXU3201548',
      vesselName: 'HYUNDAI COURAGE',
      customsRequired: true,
      insuranceRequired: false,
      cargoType: '의류 및 직물',
      events: [
        ShipmentEvent(
          id: 'evt-002-1',
          status: ShipmentStatus.registered,
          timestamp: DateTime(2026, 6, 1, 10, 0),
          location: '서울, 대한민국',
          description: '화물 등록',
        ),
        ShipmentEvent(
          id: 'evt-002-2',
          status: ShipmentStatus.bookingConfirmed,
          timestamp: DateTime(2026, 6, 3, 15, 0),
          location: '인천항',
          description: '예약 확정',
        ),
        ShipmentEvent(
          id: 'evt-002-3',
          status: ShipmentStatus.loadingComplete,
          timestamp: DateTime(2026, 6, 10, 7, 30),
          location: '인천항',
          description: '선적 완료',
        ),
        ShipmentEvent(
          id: 'evt-002-4',
          status: ShipmentStatus.inTransit,
          timestamp: DateTime(2026, 6, 11, 5, 0),
          location: '인천항 출항',
          description: '출항',
        ),
        ShipmentEvent(
          id: 'evt-002-5',
          status: ShipmentStatus.inCustoms,
          timestamp: DateTime(2026, 7, 5, 9, 0),
          location: '비엔티안 ICD',
          description: '라오스 세관 통관 진행 중',
        ),
        ShipmentEvent(
          id: 'evt-002-6',
          status: ShipmentStatus.delivered,
          timestamp: DateTime(2026, 7, 9, 14, 0),
          location: '비엔티안, 라오스',
          description: '화물 인도 완료',
        ),
      ],
    ),

    Shipment(
      id: 'ship-003',
      trackingNumber: 'IC-2026-00130',
      customerName: '한라무역(주)',
      customerId: 'partner-001',
      origin: '인천국제공항 (ICN)',
      destination: '비엔티안 왓따이공항 (VTE)',
      route: TransportRoute.krLaosAirExport,
      status: ShipmentStatus.bookingConfirmed,
      createdAt: DateTime(2026, 8, 1),
      estimatedArrival: DateTime(2026, 8, 10),
      weightKg: 120.0,
      volumeCbm: 0.8,
      flightNumber: 'OZ747',
      customsRequired: true,
      insuranceRequired: true,
      cargoType: '정밀 의료기기',
      events: [
        ShipmentEvent(
          id: 'evt-003-1',
          status: ShipmentStatus.registered,
          timestamp: DateTime(2026, 8, 1, 11, 0),
          location: '서울, 대한민국',
          description: '화물 등록',
        ),
        ShipmentEvent(
          id: 'evt-003-2',
          status: ShipmentStatus.bookingConfirmed,
          timestamp: DateTime(2026, 8, 2, 16, 0),
          location: '인천국제공항',
          description: '항공편 예약 확정 OZ747',
        ),
      ],
    ),

    Shipment(
      id: 'ship-004',
      trackingNumber: 'IC-2026-00098',
      customerName: '라오-코리아 트레이드',
      customerId: 'partner-002',
      origin: '비엔티안 왓따이공항 (VTE)',
      destination: '인천국제공항 (ICN)',
      route: TransportRoute.laosKrAirImport,
      status: ShipmentStatus.inCustoms,
      createdAt: DateTime(2026, 7, 25),
      estimatedArrival: DateTime(2026, 8, 5),
      weightKg: 45.0,
      volumeCbm: 0.3,
      flightNumber: 'OZ748',
      customsRequired: true,
      insuranceRequired: false,
      cargoType: '농산물 (커피원두)',
      events: [
        ShipmentEvent(
          id: 'evt-004-1',
          status: ShipmentStatus.registered,
          timestamp: DateTime(2026, 7, 25, 8, 0),
          location: '비엔티안, 라오스',
          description: '화물 등록',
        ),
        ShipmentEvent(
          id: 'evt-004-2',
          status: ShipmentStatus.bookingConfirmed,
          timestamp: DateTime(2026, 7, 26, 10, 0),
          location: '비엔티안 공항',
          description: '항공편 예약 확정',
        ),
        ShipmentEvent(
          id: 'evt-004-3',
          status: ShipmentStatus.loadingComplete,
          timestamp: DateTime(2026, 8, 1, 6, 0),
          location: '비엔티안 왓따이공항',
          description: '화물 탑재 완료',
        ),
        ShipmentEvent(
          id: 'evt-004-4',
          status: ShipmentStatus.inTransit,
          timestamp: DateTime(2026, 8, 1, 8, 30),
          location: '비엔티안 출항',
          description: '출발',
        ),
        ShipmentEvent(
          id: 'evt-004-5',
          status: ShipmentStatus.inCustoms,
          timestamp: DateTime(2026, 8, 2, 14, 0),
          location: '인천국제공항',
          description: '한국 세관 신고 진행 중',
        ),
      ],
    ),
  ];

  // 화물 번호 검색
  static Shipment? findByTracking(String trackingNumber) {
    try {
      return all.firstWhere(
            (s) => s.trackingNumber.toLowerCase() ==
            trackingNumber.trim().toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  // 고객 ID로 필터
  static List<Shipment> forCustomer(String customerId) =>
      all.where((s) => s.customerId == customerId).toList();
}

// ============================================================
// Mock 견적 요청 데이터 (런타임에서 추가됨)
// TODO: Supabase로 교체 시 삭제
// ============================================================
class MockQuoteRequests {
  static final List<QuoteRequest> _data = [
    QuoteRequest(
      id: 'qr-001',
      customerName: '정수빈',
      contactPhone: '010-3456-7890',
      contactEmail: 'subin@personal.com',
      origin: '서울',
      destination: '비엔티안',
      transportMode: QuoteTransportMode.sea,
      desiredShipDate: DateTime(2026, 9, 1),
      cargoType: '가전제품',
      quantity: 5,
      totalWeightKg: 180.0,
      lengthCm: 80,
      widthCm: 60,
      heightCm: 50,
      packagingStatus: PackagingStatus.packed,
      customsRequired: true,
      insuranceRequired: true,
      additionalNotes: '파손 주의 제품이 포함되어 있습니다.',
      status: QuoteStatus.reviewing,
      createdAt: DateTime(2026, 8, 1, 10, 30),
    ),
    QuoteRequest(
      id: 'qr-002',
      customerName: '최예진',
      contactPhone: '010-7777-8888',
      contactEmail: null,
      origin: '부산',
      destination: '방콕 (경유 비엔티안)',
      transportMode: QuoteTransportMode.undecided,
      cargoType: '개인 이삿짐',
      quantity: 1,
      totalWeightKg: 350.0,
      lengthCm: 200,
      widthCm: 150,
      heightCm: 180,
      packagingStatus: PackagingStatus.partial,
      customsRequired: false,
      insuranceRequired: false,
      additionalNotes: '라오스 이사 예정. 추천 운송수단 문의.',
      status: QuoteStatus.pending,
      createdAt: DateTime(2026, 8, 3, 14, 15),
    ),
  ];

  static List<QuoteRequest> get all => List.unmodifiable(_data);

  // TODO: Supabase INSERT API 호출로 교체
  static void add(QuoteRequest request) {
    _data.add(request);
  }

  static int get pendingCount =>
      _data.where((q) => q.status == QuoteStatus.pending).length;

  static List<QuoteRequest> get recent =>
      (_data.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          .take(5)
          .toList();
}

// ============================================================
// Mock 엑셀 업로드 결과 (관리자 화면용)
// TODO: excel 패키지 + 실제 파일 파싱으로 교체
// ============================================================
class MockExcelUploadResult {
  final int successCount;
  final int errorCount;
  final List<String> errorMessages;
  final DateTime uploadedAt;

  const MockExcelUploadResult({
    required this.successCount,
    required this.errorCount,
    required this.errorMessages,
    required this.uploadedAt,
  });
}
