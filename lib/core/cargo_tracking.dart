enum CargoTrackingMode { sea, air }

enum CargoTrackingVehicle { truck, ship, plane }

class CargoTrackingLeg {
  const CargoTrackingLeg({
    required this.from,
    required this.to,
    required this.vehicle,
    required this.fromProgress,
    required this.toProgress,
  });

  final String from;
  final String to;
  final CargoTrackingVehicle vehicle;
  final double fromProgress;
  final double toProgress;
}

class CargoTracking {
  CargoTracking._();

  static String _text(dynamic value) => '${value ?? ''}'.trim();

  static String _normalize(dynamic value) => _text(value)
      .toLowerCase()
      .replaceAll(RegExp(r'항차|voyage|v(?=\d)'), '')
      .replaceAll(RegExp(r'[^a-z0-9가-힣ກ-ໝ]'), '');

  static String _routeSignature(dynamic value) => _normalize(_text(value)
      .toLowerCase()
      .replaceAll('한국', 'kr')
      .replaceAll('korea', 'kr')
      .replaceAll('kor', 'kr')
      .replaceAll('라오스', 'la')
      .replaceAll('laos', 'la')
      .replaceAll('lao', 'la')
      .replaceAll('태국', 'th')
      .replaceAll('thailand', 'th')
      .replaceAll('베트남', 'vn')
      .replaceAll('vietnam', 'vn')
      .replaceAll('중국', 'cn')
      .replaceAll('china', 'cn')
      .replaceAll('캄보디아', 'kh')
      .replaceAll('cambodia', 'kh')
      .replaceAll('항공 특송', 'airexp')
      .replaceAll('air express', 'airexp')
      .replaceAll('항공', 'air')
      .replaceAll('flight', 'air')
      .replaceAll('해상', 'sea')
      .replaceAll('ocean', 'sea')
      .replaceAll('선박', 'sea')
      .replaceAll('육로', 'land'));

  static int yearOf(dynamic value) =>
      int.tryParse(RegExp(r'\d{4}').firstMatch(_text(value))?.group(0) ?? '') ?? 0;

  static String voyageOf(dynamic value) =>
      _normalize(value).replaceFirst(RegExp(r'^0+(?=\d)'), '');

  static CargoTrackingMode? modeOf(Map<String, dynamic> row) {
    final text = '${_text(row['route'])} ${_text(row['route_category'])}'.toLowerCase();
    if (RegExp(r'항공|air|flight|lka').hasMatch(text)) {
      return CargoTrackingMode.air;
    }
    if (RegExp(r'해상|ocean|sea|선박|lks').hasMatch(text)) {
      return CargoTrackingMode.sea;
    }
    return null;
  }

  static bool matches(
    Map<String, dynamic> cargo,
    Map<String, dynamic> schedule,
  ) {
    final cargoYear = yearOf(cargo['shipment_year'] ?? cargo['year']);
    final scheduleYear = yearOf(schedule['year'] ?? schedule['shipment_year']);
    if (cargoYear == 0 || scheduleYear == 0 || cargoYear != scheduleYear) {
      return false;
    }
    final cargoVoyage = voyageOf(cargo['voyage']);
    final scheduleVoyage = voyageOf(schedule['voyage']);
    if (cargoVoyage.isEmpty ||
        scheduleVoyage.isEmpty ||
        cargoVoyage != scheduleVoyage) {
      return false;
    }
    final cargoRoute = _routeSignature(cargo['route']);
    final scheduleRoute = _routeSignature(schedule['route']);
    if (cargoRoute.isNotEmpty && scheduleRoute.isNotEmpty) {
      return cargoRoute == scheduleRoute;
    }
    final cargoMode = modeOf(cargo);
    return cargoMode != null && cargoMode == modeOf(schedule);
  }

  static Map<String, dynamic>? findSchedule(
    Map<String, dynamic> cargo,
    Iterable<Map<String, dynamic>> schedules,
  ) {
    for (final schedule in schedules) {
      if (schedule['deleted_at'] != null ||
          schedule['is_visible'] == false ||
          schedule['deletion_status'] == 'pending' ||
          schedule['deletion_status'] == 'deleted') {
        continue;
      }
      if (matches(cargo, schedule)) return schedule;
    }
    return null;
  }

  static DateTime? _date(dynamic value) {
    final text = _text(value);
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  static DateTime? startDate(Map<String, dynamic> schedule) =>
      _date(schedule['departure_date'] ??
          schedule['etd'] ??
          schedule['booking_close_date']);

  static DateTime? endDate(Map<String, dynamic> schedule) =>
      _date(schedule['arrival_date'] ??
          schedule['eta'] ??
          schedule['estimated_arrival_date']);

  static double progress(
    Map<String, dynamic> schedule, {
    DateTime? now,
  }) {
    final status = _text(schedule['status']).toLowerCase();
    if (RegExp(r'arriv|deliver|complete|도착|완료').hasMatch(status)) return 1;
    final start = startDate(schedule);
    final end = endDate(schedule);
    if (start == null || end == null || !end.isAfter(start)) return 0;
    final current = now ?? DateTime.now();
    if (!current.isAfter(start)) return 0;
    if (!current.isBefore(end)) return 1;
    return current.difference(start).inMilliseconds /
        end.difference(start).inMilliseconds;
  }

  static List<CargoTrackingLeg> legs(CargoTrackingMode mode) {
    if (mode == CargoTrackingMode.air) {
      return const [
        CargoTrackingLeg(
          from: 'incheonCenter',
          to: 'incheonAirport',
          vehicle: CargoTrackingVehicle.truck,
          fromProgress: 0,
          toProgress: .08,
        ),
        CargoTrackingLeg(
          from: 'incheonAirport',
          to: 'wattay',
          vehicle: CargoTrackingVehicle.plane,
          fromProgress: .08,
          toProgress: .88,
        ),
        CargoTrackingLeg(
          from: 'wattay',
          to: 'lkCenter',
          vehicle: CargoTrackingVehicle.truck,
          fromProgress: .88,
          toProgress: 1,
        ),
      ];
    }
    return const [
      CargoTrackingLeg(
        from: 'incheonCenter',
        to: 'incheonPort',
        vehicle: CargoTrackingVehicle.truck,
        fromProgress: 0,
        toProgress: .07,
      ),
      CargoTrackingLeg(
        from: 'incheonPort',
        to: 'laemChabang',
        vehicle: CargoTrackingVehicle.ship,
        fromProgress: .07,
        toProgress: .75,
      ),
      CargoTrackingLeg(
        from: 'laemChabang',
        to: 'vientiane',
        vehicle: CargoTrackingVehicle.truck,
        fromProgress: .75,
        toProgress: .94,
      ),
      CargoTrackingLeg(
        from: 'vientiane',
        to: 'lkCenter',
        vehicle: CargoTrackingVehicle.truck,
        fromProgress: .94,
        toProgress: 1,
      ),
    ];
  }

  static CargoTrackingLeg currentLeg(
    CargoTrackingMode mode,
    double progress,
  ) {
    final values = legs(mode);
    for (final leg in values) {
      if (progress <= leg.toProgress) return leg;
    }
    return values.last;
  }

  static DateTime? legDate(
    Map<String, dynamic> schedule,
    double progress,
  ) {
    final start = startDate(schedule);
    final end = endDate(schedule);
    if (start == null || end == null || !end.isAfter(start)) return null;
    return start.add(Duration(
      milliseconds:
          (end.difference(start).inMilliseconds * progress).round(),
    ));
  }
}
