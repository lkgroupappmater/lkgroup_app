import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/cargo_tracking.dart';
import '../core/route_catalog.dart';
import '../core/shipment_period_labels.dart';
import '../services/schedule_service.dart';

class CargoTrackingLabels {
  CargoTrackingLabels._();

  static const _values = <String, List<String>>{
    'title': ['물품 이동 현황', 'Cargo movement', 'ສະຖານະການເຄື່ອນຍ້າຍສິນຄ້າ'],
    'current': ['현재 예상 위치', 'Current estimated location', 'ຕຳແໜ່ງຄາດຄະເນປັດຈຸບັນ'],
    'preparing': ['출발 준비', 'Preparing', 'ກຳລັງກຽມອອກ'],
    'moving': ['운송 진행 예상', 'Estimated in transit', 'ຄາດວ່າກຳລັງຂົນສົ່ງ'],
    'arriving': ['도착 예정 구간', 'Arrival stage', 'ຂັ້ນຕອນຮອດ'],
    'arrived': ['도착', 'Arrived', 'ຮອດແລ້ວ'],
    'dispatching': ['출고중', 'Dispatching', 'ກຳລັງຈັດສົ່ງ'],
    'loading': ['선적 일정을 연결하는 중입니다.', 'Linking the shipping schedule.', 'ກຳລັງເຊື່ອມຕໍ່ຕາຕະລາງ.'],
    'missing': ['연결된 선적 일정이 없어 현재 예상 위치를 계산할 수 없습니다.', 'No linked shipping schedule is available to estimate the current location.', 'ບໍ່ມີຕາຕະລາງທີ່ເຊື່ອມຕໍ່ ເພື່ອຄາດຄະເນຕຳແໜ່ງ.'],
    'notLinkedShort': ['일정 연결 확인', 'Check schedule link', 'ກວດກາຕາຕະລາງ'],
    'note': ['표시 위치와 구간 날짜는 등록 일정의 접수 마감일·도착 예정일로 계산한 예상치이며 실시간 GPS 위치가 아닙니다.', 'Positions and segment dates are estimates calculated from the registered booking-close and ETA dates, not live GPS.', 'ຕຳແໜ່ງ ແລະ ວັນທີແມ່ນຄ່າຄາດຄະເນຈາກວັນປິດຮັບ ແລະ ETA, ບໍ່ແມ່ນ GPS ແບບສົດ.'],
    'booking': ['접수 마감', 'Booking close', 'ປິດຮັບ'],
    'eta': ['도착 예정', 'Estimated arrival', 'ຄາດວ່າຮອດ'],
    'legs': ['구간별 예상 일정', 'Estimated route legs', 'ຕາຕະລາງຄາດຄະເນແຕ່ລະຊ່ວງ'],
    'truck': ['컨테이너 차량', 'Container truck', 'ລົດບັນທຸກຕູ້'],
    'ship': ['컨테이너 선박', 'Container vessel', 'ເຮືອຕູ້ຄອນເທນເນີ'],
    'plane': ['항공기', 'Aircraft', 'ເຮືອບິນ'],
    'box': ['화물번호', 'Cargo number', 'ເລກສິນຄ້າ'],
    'invoice': ['송장번호', 'Invoice number', 'ເລກໃບຂົນສົ່ງ'],
    'route': ['운송 경로', 'Route', 'ເສັ້ນທາງ'],
    'period': ['년도 / 항차', 'Year / Voyage', 'ປີ / ຖ້ຽວ'],
    'close': ['닫기', 'Close', 'ປິດ'],
    'incheonCenter': ['한국 인천 물류센터', 'Incheon Logistics Center', 'ສູນໂລຈິສຕິກອິນຊອນ'],
    'incheonPort': ['한국 인천항', 'Port of Incheon', 'ທ່າເຮືອອິນຊອນ'],
    'incheonAirport': ['인천 국제공항', 'Incheon Int’l Airport', 'ສະໜາມບິນອິນຊອນ'],
    'laemChabang': ['태국 람챠방항', 'Laem Chabang Port', 'ທ່າເຮືອແຫຼມສະບັງ'],
    'vientiane': ['라오스 비엔티엔', 'Vientiane', 'ວຽງຈັນ'],
    'wattay': ['라오스 와따이 공항', 'Wattay Int’l Airport', 'ສະໜາມບິນວັດໄຕ'],
    'lkCenter': ['LKGroup 물류센터', 'LKGroup Logistics Center', 'ສູນໂລຈິສຕິກ LKGroup'],
  };

  static int _index(AppLanguage language) {
    switch (language) {
      case AppLanguage.korean:
        return 0;
      case AppLanguage.english:
        return 1;
      case AppLanguage.lao:
        return 2;
    }
  }

  static String text(AppLanguage language, String key) =>
      _values[key]?[_index(language)] ?? key;

  static String location(AppLanguage language, String key) =>
      text(language, key);

  static String vehicle(
    AppLanguage language,
    CargoTrackingVehicle vehicle,
  ) {
    return text(language, vehicle.name);
  }

  static String summary(
    AppLanguage language,
    Map<String, dynamic>? schedule,
  ) {
    if (schedule == null) return text(language, 'missing');
    final phase = CargoTracking.phase(schedule);
    if (phase == CargoTrackingPhase.arrived) {
      return '${text(language, 'arrived')} · ${location(language, 'lkCenter')}';
    }
    if (phase == CargoTrackingPhase.dispatching) {
      return '${text(language, 'dispatching')} · ${location(language, 'lkCenter')}';
    }
    final mode = CargoTracking.modeOf(schedule) ?? CargoTrackingMode.sea;
    final progress = CargoTracking.progress(schedule);
    final leg = CargoTracking.currentLeg(mode, progress);
    final state = progress <= 0
        ? text(language, 'preparing')
        : progress >= .94
            ? text(language, 'arriving')
            : text(language, 'moving');
    return '$state · ${location(language, leg.from)} → '
        '${location(language, leg.to)} · ${vehicle(language, leg.vehicle)}';
  }
}

class CargoTrackingDialog {
  CargoTrackingDialog._();

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> cargo,
    required AppLanguage language,
    Map<String, dynamic>? schedule,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _CargoTrackingDialogBody(
        cargo: cargo,
        language: language,
        initialSchedule: schedule,
      ),
    );
  }
}

class _CargoTrackingDialogBody extends StatefulWidget {
  const _CargoTrackingDialogBody({
    required this.cargo,
    required this.language,
    this.initialSchedule,
  });

  final Map<String, dynamic> cargo;
  final AppLanguage language;
  final Map<String, dynamic>? initialSchedule;

  @override
  State<_CargoTrackingDialogBody> createState() =>
      _CargoTrackingDialogBodyState();
}

class _CargoTrackingDialogBodyState
    extends State<_CargoTrackingDialogBody> {
  late final Future<Map<String, dynamic>?> _schedule;

  String _t(String key) => CargoTrackingLabels.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _schedule = widget.initialSchedule == null
        ? ScheduleService.instance.findForCargo(widget.cargo)
        : Future.value(widget.initialSchedule);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: math.max(420.0, size.height - 40).toDouble(),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
              color: AppColors.navyPrimary,
              child: Row(
                children: [
                  const Icon(Icons.route_outlined, color: Colors.white),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _t('title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _schedule,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(_t('loading')),
                        ],
                      ),
                    );
                  }
                  return _TrackingContent(
                    cargo: widget.cargo,
                    schedule: snapshot.data,
                    language: widget.language,
                    error: snapshot.hasError ? '${snapshot.error}' : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingContent extends StatelessWidget {
  const _TrackingContent({
    required this.cargo,
    required this.schedule,
    required this.language,
    this.error,
  });

  final Map<String, dynamic> cargo;
  final Map<String, dynamic>? schedule;
  final AppLanguage language;
  final String? error;

  String _t(String key) => CargoTrackingLabels.text(language, key);

  String _date(DateTime? value) {
    if (value == null) return '-';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Widget _reference(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFE),
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            '$value'.trim().isEmpty ? '-' : '$value',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.navyPrimary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _vehicleIcon(CargoTrackingVehicle vehicle) {
    switch (vehicle) {
      case CargoTrackingVehicle.truck:
        return Icons.local_shipping_outlined;
      case CargoTrackingVehicle.ship:
        return Icons.directions_boat_filled;
      case CargoTrackingVehicle.plane:
        return Icons.flight_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = CargoTracking.modeOf(schedule ?? cargo) ?? CargoTrackingMode.sea;
    final progress = schedule == null ? 0.0 : CargoTracking.progress(schedule!);
    final current = CargoTracking.currentLeg(mode, progress);
    final legs = CargoTracking.legs(mode);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 580 ? 4 : 2;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
                childAspectRatio: columns == 4 ? 2.35 : 2.1,
                children: [
                  _reference(_t('box'), cargo['box_number'] ?? '-'),
                  _reference(_t('invoice'), cargo['invoice_number'] ?? '-'),
                  _reference(
                    _t('route'),
                    RouteCatalog.localizedLabel(
                      '${cargo['route'] ?? ''}',
                      language,
                    ),
                  ),
                  _reference(
                    _t('period'),
                    '${ShipmentPeriodLabels.year(cargo['shipment_year'] ?? cargo['year'], language)} / '
                        '${ShipmentPeriodLabels.voyage(cargo['voyage'], language)}',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          CargoRouteMap(
            mode: mode,
            progress: schedule == null ? null : progress,
            language: language,
          ),
          const SizedBox(height: 12),
          if (error != null || schedule == null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E7),
                border: Border.all(color: const Color(0xFFF0D79A)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(error ?? _t('missing')),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3FAFE),
                border: Border.all(color: const Color(0xFFB9DEEA)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('current'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CargoTrackingLabels.summary(language, schedule),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.navyPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(8),
                    color: mode == CargoTrackingMode.air
                        ? const Color(0xFFF0A344)
                        : AppColors.tealAccent,
                    backgroundColor: AppColors.divider,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_t('booking')} ${_date(CargoTracking.startDate(schedule!))}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Text(
                        '${_t('eta')} ${_date(CargoTracking.endDate(schedule!))}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _t('legs'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.navyPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ...legs.map((leg) {
              final active = leg.from == current.from && leg.to == current.to;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFEAF8FC) : Colors.white,
                  border: Border.all(
                    color: active
                        ? AppColors.tealAccent
                        : AppColors.divider,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    Icon(
                      _vehicleIcon(leg.vehicle),
                      size: 21,
                      color: active
                          ? AppColors.navyPrimary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${CargoTrackingLabels.location(language, leg.from)} → '
                            '${CargoTrackingLabels.location(language, leg.to)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            CargoTrackingLabels.vehicle(language, leg.vehicle),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_date(CargoTracking.legDate(schedule!, leg.fromProgress))}\n'
                      '${_date(CargoTracking.legDate(schedule!, leg.toProgress))}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.navyPrimary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              _t('note'),
              style: const TextStyle(
                color: Color(0xFFCDE7F2),
                height: 1.45,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CargoRouteMap extends StatefulWidget {
  const CargoRouteMap({
    super.key,
    required this.mode,
    required this.progress,
    required this.language,
  });

  final CargoTrackingMode mode;
  final double? progress;
  final AppLanguage language;

  @override
  State<CargoRouteMap> createState() => _CargoRouteMapState();
}

class _CargoRouteMapState extends State<CargoRouteMap>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _motion;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _setZoom(double value) {
    setState(() {
      _zoom = value.clamp(1.0, 3.0).toDouble();
      _transform.value = Matrix4.diagonal3Values(_zoom, _zoom, 1);
    });
  }

  Widget _control(IconData icon, VoidCallback action, String tooltip) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: action,
      color: Colors.white,
      iconSize: 18,
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 760 / 500,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 3,
                boundaryMargin: const EdgeInsets.all(90),
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: _CargoRoutePainter(
                      mode: widget.mode,
                      progress: widget.progress,
                      language: widget.language,
                      motion: _motion,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xDD082D55),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _control(Icons.add, () => _setZoom(_zoom + .4), 'Zoom in'),
                    _control(Icons.remove, () => _setZoom(_zoom - .4), 'Zoom out'),
                    _control(Icons.home_outlined, () => _setZoom(1), 'Reset'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CargoRoutePainter extends CustomPainter {
  _CargoRoutePainter({
    required this.mode,
    required this.progress,
    required this.language,
    required Animation<double> motion,
  }) : super(repaint: motion),
       _motion = motion;

  final CargoTrackingMode mode;
  final double? progress;
  final AppLanguage language;
  final Animation<double> _motion;

  Path _polygon(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  Path _seaPath() => Path()
    ..moveTo(650, 60)
    ..lineTo(643, 72)
    ..moveTo(643, 72)
    ..cubicTo(675, 105, 690, 150, 676, 208)
    ..cubicTo(660, 276, 622, 334, 563, 382)
    ..cubicTo(490, 440, 406, 470, 315, 482)
    ..cubicTo(236, 493, 174, 488, 118, 475)
    ..moveTo(118, 475)
    ..cubicTo(132, 448, 153, 414, 181, 389)
    ..lineTo(191, 383);

  Path _airPath() => Path()
    ..moveTo(650, 60)
    ..lineTo(637, 55)
    ..moveTo(637, 55)
    ..cubicTo(520, 118, 346, 236, 186, 382)
    ..moveTo(186, 382)
    ..lineTo(191, 383);

  Path _legPath(CargoTrackingMode trackingMode, int index) {
    if (trackingMode == CargoTrackingMode.air) {
      if (index == 0) return Path()..moveTo(650, 60)..lineTo(637, 55);
      if (index == 1) {
        return Path()
          ..moveTo(637, 55)
          ..cubicTo(520, 118, 346, 236, 186, 382);
      }
      return Path()..moveTo(186, 382)..lineTo(191, 383);
    }
    if (index == 0) return Path()..moveTo(650, 60)..lineTo(643, 72);
    if (index == 1) {
      return Path()
        ..moveTo(643, 72)
        ..cubicTo(675, 105, 690, 150, 676, 208)
        ..cubicTo(660, 276, 622, 334, 563, 382)
        ..cubicTo(490, 440, 406, 470, 315, 482)
        ..cubicTo(236, 493, 174, 488, 118, 475);
    }
    if (index == 2) {
      return Path()
        ..moveTo(118, 475)
        ..cubicTo(132, 448, 153, 414, 181, 389);
    }
    return Path()..moveTo(181, 389)..lineTo(191, 383);
  }

  void _label(Canvas canvas, String text, Offset point,
      {double size = 15, TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .9),
          fontSize: size,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Color(0xFF082D55), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: 250);
    final x = align == TextAlign.right ? point.dx - painter.width : point.dx;
    painter.paint(canvas, Offset(x, point.dy));
  }

  void _drawWarehouse(Canvas canvas, Offset center) {
    final fill = Paint()..color = const Color(0xFFF2FBFF);
    final outline = Paint()
      ..color = const Color(0xFF61CCE6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final roof = Path()
      ..moveTo(center.dx - 19, center.dy - 2)
      ..lineTo(center.dx, center.dy - 14)
      ..lineTo(center.dx + 19, center.dy - 2)
      ..lineTo(center.dx + 19, center.dy + 15)
      ..lineTo(center.dx - 19, center.dy + 15)
      ..close();
    canvas.drawPath(roof, fill);
    canvas.drawPath(roof, outline);
    canvas.drawRect(
      Rect.fromCenter(
          center: center.translate(0, 7), width: 25, height: 15),
      Paint()..color = const Color(0xFF174B78),
    );
  }

  void _drawRoute(Canvas canvas, Path path, Color color, bool active) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: active ? .95 : .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 4.5 : 2.5
        ..strokeCap = StrokeCap.round,
    );
    if (!active) return;
    final dot = Paint()..color = Colors.white.withValues(alpha: .78);
    for (final metric in path.computeMetrics()) {
      for (double offset = 8; offset < metric.length; offset += 19) {
        final tangent = metric.getTangentForOffset(offset);
        if (tangent != null) canvas.drawCircle(tangent.position, 2.1, dot);
      }
    }
  }

  void _drawTruck(Canvas canvas) {
    final fill = Paint()..color = const Color(0xFFF1FBFF);
    final edge = Paint()
      ..color = const Color(0xFF5ED2EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRect(const Rect.fromLTWH(-26, -11, 31, 19), fill);
    canvas.drawRect(const Rect.fromLTWH(-26, -11, 31, 19), edge);
    final cab = Path()
      ..moveTo(5, -6)
      ..lineTo(15, -6)
      ..lineTo(24, 3)
      ..lineTo(24, 8)
      ..lineTo(5, 8)
      ..close();
    canvas.drawPath(cab, fill);
    canvas.drawPath(cab, edge);
    final wheel = Paint()..color = const Color(0xFF082B50);
    canvas.drawCircle(const Offset(-17, 10), 4, wheel);
    canvas.drawCircle(const Offset(16, 10), 4, wheel);
  }

  void _drawShip(Canvas canvas) {
    final fill = Paint()..color = const Color(0xFFF1FBFF);
    final edge = Paint()
      ..color = const Color(0xFF5ED2EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final hull = Path()
      ..moveTo(-32, 5)
      ..lineTo(31, 5)
      ..lineTo(21, 17)
      ..lineTo(-22, 17)
      ..close();
    canvas.drawPath(hull, fill);
    canvas.drawPath(hull, edge);
    final box = Paint()..color = const Color(0xFFE4A43B);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(-23 + i * 16, -10, 14, 14), box);
    }
  }

  void _drawPlane(Canvas canvas) {
    final path = Path()
      ..moveTo(-25, 0)
      ..lineTo(-7, -6)
      ..lineTo(2, -20)
      ..lineTo(8, -20)
      ..lineTo(5, -5)
      ..lineTo(26, 0)
      ..lineTo(5, 6)
      ..lineTo(8, 20)
      ..lineTo(2, 20)
      ..lineTo(-7, 7)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE9A547)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawVehicle(Canvas canvas) {
    if (progress == null) return;
    final trackingMode = mode;
    final legs = CargoTracking.legs(trackingMode);
    final leg = CargoTracking.currentLeg(trackingMode, progress!);
    final legIndex = legs.indexWhere((item) =>
        item.from == leg.from &&
        item.to == leg.to &&
        item.vehicle == leg.vehicle);
    final path = _legPath(trackingMode, legIndex < 0 ? 0 : legIndex);
    final metric = path.computeMetrics().first;
    final span = math.max(.0001, leg.toProgress - leg.fromProgress);
    final localProgress =
        ((progress! - leg.fromProgress) / span).clamp(0.0, 1.0).toDouble();
    final base = metric.length * localProgress;
    final wave = math.sin(_motion.value * math.pi * 2) * 2.5;
    final tangent = metric.getTangentForOffset(
      (base + wave).clamp(0.0, metric.length).toDouble(),
    );
    if (tangent == null) return;
    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    final haloRadius = leg.vehicle == CargoTrackingVehicle.ship
        ? 29.0
        : leg.vehicle == CargoTrackingVehicle.truck
            ? 20.0
            : 25.0;
    canvas.drawCircle(
      Offset.zero,
      haloRadius,
      Paint()..color = const Color(0xBB082E57),
    );
    canvas.rotate(tangent.angle);
    switch (leg.vehicle) {
      case CargoTrackingVehicle.truck:
        canvas.scale(.82);
        _drawTruck(canvas);
        break;
      case CargoTrackingVehicle.ship:
        _drawShip(canvas);
        break;
      case CargoTrackingVehicle.plane:
        _drawPlane(canvas);
        break;
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 760, size.height / 500);
    final bounds = const Rect.fromLTWH(0, 0, 760, 500);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF103A67), Color(0xFF087196)],
        ).createShader(bounds),
    );
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= 760; x += 152) canvas.drawLine(Offset(x, 0), Offset(x, 500), grid);
    for (var y = 0.0; y <= 500; y += 100) canvas.drawLine(Offset(0, y), Offset(760, y), grid);

    final land = Paint()..color = const Color(0xFF356783);
    final edge = Paint()
      ..color = const Color(0xFF7397AA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final countries = <Path>[
      _polygon(const [Offset(0,0),Offset(625,0),Offset(627,28),Offset(614,54),Offset(611,84),Offset(586,115),Offset(556,135),Offset(538,166),Offset(504,189),Offset(482,214),Offset(442,231),Offset(411,256),Offset(369,274),Offset(341,302),Offset(302,317),Offset(273,346),Offset(234,366),Offset(209,395),Offset(173,413),Offset(142,405),Offset(132,377),Offset(106,363),Offset(79,330),Offset(36,321),Offset(0,289)]),
      _polygon(const [Offset(631,24),Offset(653,29),Offset(667,48),Offset(665,73),Offset(653,94),Offset(640,107),Offset(628,97),Offset(631,77),Offset(623,59),Offset(630,43)]),
      _polygon(const [Offset(701,37),Offset(712,45),Offset(706,69),Offset(693,86),Offset(688,112),Offset(676,123),Offset(670,116),Offset(677,93),Offset(687,76),Offset(692,49)]),
      _polygon(const [Offset(523,216),Offset(533,225),Offset(529,254),Offset(517,270),Offset(509,263),Offset(513,237)]),
      _polygon(const [Offset(242,309),Offset(257,325),Offset(252,349),Offset(264,374),Offset(256,402),Offset(265,431),Offset(253,464),Offset(238,456),Offset(244,428),Offset(230,406),Offset(235,377),Offset(222,357),Offset(229,329)]),
      _polygon(const [Offset(183,339),Offset(212,326),Offset(232,342),Offset(227,369),Offset(242,392),Offset(226,421),Offset(198,416),Offset(178,385)]),
      _polygon(const [Offset(103,371),Offset(145,359),Offset(179,379),Offset(196,416),Offset(182,442),Offset(196,478),Offset(183,500),Offset(132,500),Offset(124,469),Offset(93,446),Offset(81,408)]),
      _polygon(const [Offset(185,421),Offset(225,418),Offset(252,440),Offset(244,471),Offset(202,479),Offset(182,450)]),
    ];
    for (final country in countries) {
      canvas.drawPath(country, land);
      canvas.drawPath(country, edge);
    }

    _label(canvas, 'CHINA', const Offset(468, 104), size: 17);
    _label(canvas, 'KOREA', const Offset(650, 12), size: 16);
    _label(canvas, 'THAILAND', const Offset(101, 425), size: 15);
    _label(canvas, 'LAOS', const Offset(181, 374), size: 15);
    final sea = _seaPath(), air = _airPath();
    _drawRoute(canvas, sea, const Color(0xFF5BD3ED), mode == CargoTrackingMode.sea);
    _drawRoute(canvas, air, const Color(0xFFFFBE65), mode == CargoTrackingMode.air);

    final node = Paint()..color = Colors.white;
    final nodeEdge = Paint()
      ..color = const Color(0xFF4CC6E3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final point in const [Offset(643,72),Offset(637,55),Offset(118,475),Offset(181,389),Offset(186,382)]) {
      canvas.drawCircle(point, 5, node);
      canvas.drawCircle(point, 5, nodeEdge);
    }
    _drawWarehouse(canvas, const Offset(671, 48));
    _drawWarehouse(canvas, const Offset(210, 367));
    _label(canvas, CargoTrackingLabels.location(language, 'incheonCenter'), const Offset(704, 31), size: 16, align: TextAlign.right);
    _label(canvas, CargoTrackingLabels.location(language, 'lkCenter'), const Offset(239, 352), size: 16);
    _drawVehicle(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CargoRoutePainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.progress != progress ||
      oldDelegate.language != language;
}
