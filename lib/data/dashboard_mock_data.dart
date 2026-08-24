// lib/data/dashboard_mock_data.dart

import '../models/shipping_schedule.dart';
import '../models/notice.dart';
import '../models/cargo_receiving.dart';

class DashboardMockData {
  DashboardMockData._();

  static const List<ShippingSchedule> shippingSchedules = [
    ShippingSchedule(
      id: 'SS001',
      routeName: '부산 → 상하이',
      transportMode: TransportMode.sea,
      origin: '부산항',
      destination: '상하이항',
      departureDate: '2025-07-10',
      arrivalDate: '2025-07-13',
      status: ShipmentStatus.inTransit,
      referenceNo: 'LK-2025-0710-01',
    ),
    ShippingSchedule(
      id: 'SS002',
      routeName: '인천 → 로스앤젤레스',
      transportMode: TransportMode.air,
      origin: '인천국제공항',
      destination: 'LAX',
      departureDate: '2025-07-12',
      arrivalDate: '2025-07-13',
      status: ShipmentStatus.scheduled,
      referenceNo: 'LK-2025-0712-02',
    ),
    ShippingSchedule(
      id: 'SS003',
      routeName: '부산 → 함부르크',
      transportMode: TransportMode.sea,
      origin: '부산항',
      destination: '함부르크항',
      departureDate: '2025-07-08',
      arrivalDate: '2025-07-28',
      status: ShipmentStatus.atPort,
      referenceNo: 'LK-2025-0708-03',
    ),
    ShippingSchedule(
      id: 'SS004',
      routeName: '서울 → 도쿄',
      transportMode: TransportMode.air,
      origin: '김포공항',
      destination: '하네다공항',
      departureDate: '2025-07-15',
      arrivalDate: '2025-07-15',
      status: ShipmentStatus.scheduled,
      referenceNo: 'LK-2025-0715-04',
    ),
    ShippingSchedule(
      id: 'SS005',
      routeName: '평택 → 블라디보스토크',
      transportMode: TransportMode.land,
      origin: '평택항',
      destination: '블라디보스토크',
      departureDate: '2025-07-05',
      arrivalDate: '2025-07-09',
      status: ShipmentStatus.customs,
      referenceNo: 'LK-2025-0705-05',
    ),
    ShippingSchedule(
      id: 'SS006',
      routeName: '부산 → 싱가포르',
      transportMode: TransportMode.sea,
      origin: '부산항',
      destination: '싱가포르항',
      departureDate: '2025-07-18',
      arrivalDate: '2025-07-23',
      status: ShipmentStatus.scheduled,
      referenceNo: 'LK-2025-0718-06',
    ),
  ];

  static List<ShippingSchedule> get activeSchedules =>
      shippingSchedules.where((s) {
        return s.status == ShipmentStatus.inTransit ||
            s.status == ShipmentStatus.scheduled ||
            s.status == ShipmentStatus.atPort ||
            s.status == ShipmentStatus.customs;
      }).toList();

  static const List<Notice> notices = [
    Notice(
      id: 'N001',
      title: '[긴급] 상하이항 혼잡으로 인한 출항 지연 안내',
      summary: '상하이항 일시적 혼잡으로 7월 10~12일 출항 일정이 1~2일 지연될 수 있습니다.',
      content:
      '상하이항 터미널 운영 차질로 인해 해당 기간 출항 스케줄에 지연이 예상됩니다. 자세한 사항은 담당자에게 문의하시기 바랍니다.',
      date: '2025-07-09',
      category: NoticeCategory.urgent,
      isPinned: true,
    ),
    Notice(
      id: 'N002',
      title: '시스템 정기 점검 안내 (7월 14일 02:00~04:00)',
      summary: '7월 14일 새벽 시스템 점검으로 서비스 이용이 일시 중단됩니다.',
      content: '정기 점검 시간 동안 앱 및 웹 서비스 이용이 불가합니다. 양해 부탁드립니다.',
      date: '2025-07-08',
      category: NoticeCategory.system,
      isPinned: true,
    ),
    Notice(
      id: 'N003',
      title: '2025년 하반기 위험물 운송 규정 개정 안내',
      summary: '국제해사기구(IMO) 규정 개정에 따른 위험물 분류 및 포장 기준이 변경됩니다.',
      content: '2025년 7월 1일부터 적용되는 IMO 위험물 운송 규정을 반드시 확인하시기 바랍니다.',
      date: '2025-07-01',
      category: NoticeCategory.regulation,
      isPinned: false,
    ),
    Notice(
      id: 'N004',
      title: 'LK Group 창립 20주년 감사 이벤트',
      summary: '창립 20주년을 맞아 고객 감사 이벤트를 진행합니다.',
      content: '7월 한 달간 화물 운송 의뢰 고객께 특별 할인 혜택을 드립니다.',
      date: '2025-07-01',
      category: NoticeCategory.event,
      isPinned: false,
    ),
    Notice(
      id: 'N005',
      title: '여름 휴가 기간 운영 시간 변경 안내',
      summary: '7월 28일 ~ 8월 1일 하계 휴가 기간 중 운영 시간이 변경됩니다.',
      content: '해당 기간 오전 9시 ~ 오후 4시로 단축 운영됩니다.',
      date: '2025-07-07',
      category: NoticeCategory.general,
      isPinned: false,
    ),
  ];

  static const List<CargoReceiving> cargoReceivings = [
    CargoReceiving(
      receiptNo: 'CR-2025-0001',
      invoiceNo: 'INV-25-00123',
      consigneeName: '(주)한국물산',
      contact: '02-1234-5678',
      status: CargoReceivingStatus.stored,
      receivedDate: '2025-07-08',
      storageLocation: 'A동 3-15',
      shipmentNo: 'SS001',
    ),
    CargoReceiving(
      receiptNo: 'CR-2025-0002',
      invoiceNo: 'INV-25-00124',
      consigneeName: '대한전자(주)',
      contact: '031-9876-5432',
      status: CargoReceivingStatus.inspecting,
      receivedDate: '2025-07-09',
      storageLocation: 'B동 1-02',
      shipmentNo: 'SS002',
    ),
    CargoReceiving(
      receiptNo: 'CR-2025-0003',
      invoiceNo: 'INV-25-00125',
      consigneeName: '글로벌무역(주)',
      contact: '051-5555-1234',
      status: CargoReceivingStatus.readyToShip,
      receivedDate: '2025-07-07',
      storageLocation: 'C동 2-08',
      shipmentNo: 'SS003',
    ),
    CargoReceiving(
      receiptNo: 'CR-2025-0004',
      invoiceNo: 'INV-25-00126',
      consigneeName: '미래로지스틱스',
      contact: '032-7777-8888',
      status: CargoReceivingStatus.received,
      receivedDate: '2025-07-09',
      storageLocation: '미배정',
      shipmentNo: '',
    ),
    CargoReceiving(
      receiptNo: 'CR-2025-0005',
      invoiceNo: 'INV-25-00127',
      consigneeName: '(주)태평양교역',
      contact: '02-3333-4444',
      status: CargoReceivingStatus.shipped,
      receivedDate: '2025-07-03',
      storageLocation: '출고',
      shipmentNo: 'SS005',
    ),
  ];
}
