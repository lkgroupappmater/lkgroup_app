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
    'sea': ['해상', 'Ocean', 'ທາງເຮືອ'],
    'land': ['육로', 'Road', 'ທາງບົກ'],
    'air': ['항공', 'Air', 'ທາງອາກາດ'],
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
    final phase = schedule == null ? null : CargoTracking.phase(schedule!);
    final arrivalDateLabel = phase == CargoTrackingPhase.dispatching
        ? _t('dispatching')
        : phase == CargoTrackingPhase.arrived
            ? _t('arrived')
            : _t('eta');
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
                        '$arrivalDateLabel ${_date(CargoTracking.endDate(schedule!))}',
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
  }) : _motion = motion,
       super(repaint: motion);

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

  Path _landPath() => Path()
    ..moveTo(575, 96)
    ..lineTo(563, 106)
    ..moveTo(575, 96)
    ..lineTo(557, 93)
    ..moveTo(169, 409)
    ..cubicTo(171, 392, 180, 374, 188, 362)
    ..cubicTo(193, 355, 195, 350, 195, 346)
    ..moveTo(195, 346)
    ..lineTo(207, 337);

  Path _seaPath() => Path()
    ..moveTo(563, 106)
    ..cubicTo(564, 150, 545, 185, 515, 220)
    ..cubicTo(495, 242, 478, 260, 467, 285)
    ..cubicTo(445, 330, 402, 368, 346, 404)
    ..cubicTo(315, 424, 292, 445, 268, 463)
    ..cubicTo(240, 482, 197, 472, 180, 450)
    ..cubicTo(167, 434, 163, 420, 169, 409);

  Path _airPath() => Path()
    ..moveTo(557, 93)
    ..cubicTo(470, 160, 350, 246, 195, 346);

  Path _legPath(CargoTrackingMode trackingMode, int index) {
    if (trackingMode == CargoTrackingMode.air) {
      if (index == 0) return Path()..moveTo(575, 96)..lineTo(557, 93);
      if (index == 1) {
        return Path()
          ..moveTo(557, 93)
          ..cubicTo(470, 160, 350, 246, 195, 346);
      }
      return Path()..moveTo(195, 346)..lineTo(207, 337);
    }
    if (index == 0) return Path()..moveTo(575, 96)..lineTo(563, 106);
    if (index == 1) {
      return Path()
        ..moveTo(563, 106)
        ..cubicTo(564, 150, 545, 185, 515, 220)
        ..cubicTo(495, 242, 478, 260, 467, 285)
        ..cubicTo(445, 330, 402, 368, 346, 404)
        ..cubicTo(315, 424, 292, 445, 268, 463)
        ..cubicTo(240, 482, 197, 472, 180, 450)
        ..cubicTo(167, 434, 163, 420, 169, 409);
    }
    if (index == 2) {
      return Path()
        ..moveTo(169, 409)
        ..cubicTo(171, 392, 180, 374, 188, 362)
        ..cubicTo(193, 355, 195, 350, 195, 346);
    }
    return Path()..moveTo(195, 346)..lineTo(207, 337);
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
      _polygon(const <Offset>[
        Offset(315.5, 337.5), Offset(302.1, 343.6), Offset(289.3, 339.6), Offset(288.9, 328.6), Offset(296.5, 322.8),
        Offset(313.5, 319.2), Offset(322.4, 319.5), Offset(325.9, 324.4), Offset(319.1, 330.1),
      ]),
      _polygon(const <Offset>[
        Offset(637.5, 0.0), Offset(636.3, 0.4), Offset(640.4, 11.4), Offset(638.2, 26.5), Offset(630.2, 26.9),
        Offset(630.3, 33.4), Offset(620.3, 25.8), Offset(614.2, 33.0), Offset(590.2, 38.5), Offset(592.6, 45.3),
        Offset(579.2, 44.8), Offset(571.8, 40.8), Offset(561.2, 49.9), Offset(544.1, 56.8), Offset(531.5, 65.0),
        Offset(509.8, 68.7), Offset(498.4, 74.7), Offset(481.7, 78.2), Offset(489.9, 72.3), Offset(486.7, 67.3),
        Offset(498.9, 58.7), Offset(490.7, 52.0), Offset(477.2, 56.5), Offset(459.7, 65.4), Offset(450.2, 73.7),
        Offset(434.9, 74.3), Offset(427.0, 80.3), Offset(435.2, 89.0), Offset(447.9, 91.1), Offset(448.4, 96.8),
        Offset(460.7, 100.6), Offset(478.1, 91.4), Offset(491.8, 96.4), Offset(501.9, 96.7), Offset(504.4, 103.5),
        Offset(482.4, 107.0), Offset(475.2, 114.0), Offset(460.1, 120.4), Offset(452.1, 129.4), Offset(468.8, 136.4),
        Offset(474.9, 149.0), Offset(484.4, 160.8), Offset(494.9, 170.6), Offset(494.7, 180.1), Offset(484.9, 183.6),
        Offset(488.6, 190.5), Offset(497.8, 194.5), Offset(495.4, 204.9), Offset(491.4, 215.1), Offset(482.8, 216.2),
        Offset(471.4, 230.1), Offset(458.9, 246.9), Offset(444.5, 262.2), Offset(423.1, 274.0), Offset(401.6, 284.8),
        Offset(384.1, 286.3), Offset(374.6, 292.0), Offset(369.2, 287.8), Offset(360.5, 294.2), Offset(338.8, 300.6),
        Offset(322.4, 302.6), Offset(317.1, 316.1), Offset(308.5, 316.9), Offset(304.4, 307.6), Offset(308.1, 302.6),
        Offset(287.3, 298.5), Offset(280.0, 300.6), Offset(264.3, 297.3), Offset(257.0, 292.1), Offset(259.4, 284.7),
        Offset(245.2, 282.3), Offset(237.8, 277.5), Offset(224.5, 284.4), Offset(209.5, 285.8), Offset(197.1, 285.8),
        Offset(188.8, 288.9), Offset(180.7, 290.8), Offset(183.1, 305.5), Offset(174.8, 305.1), Offset(173.4, 302.1),
        Offset(172.9, 296.8), Offset(161.6, 300.5), Offset(154.8, 298.2), Offset(143.3, 293.4), Offset(147.8, 282.7),
        Offset(138.0, 280.2), Offset(134.3, 268.4), Offset(118.0, 270.5), Offset(119.8, 255.3), Offset(134.5, 244.6),
        Offset(135.1, 234.1), Offset(134.7, 224.2), Offset(127.9, 221.2), Offset(122.7, 213.6), Offset(113.6, 214.6),
        Offset(96.9, 212.7), Offset(102.2, 207.3), Offset(94.9, 199.3), Offset(83.8, 204.7), Offset(70.8, 201.6),
        Offset(52.9, 209.7), Offset(38.8, 219.3), Offset(26.3, 220.9), Offset(19.5, 217.4), Offset(11.3, 217.1),
        Offset(0.2, 214.1), Offset(0.0, 214.2), Offset(0.0, 0.0), Offset(50.3, 0.0), Offset(54.0, 0.3),
        Offset(72.7, 8.3), Offset(82.3, 9.7), Offset(89.4, 21.5), Offset(98.5, 29.2), Offset(115.6, 28.9),
        Offset(147.6, 31.7), Offset(168.2, 30.0), Offset(183.5, 31.9), Offset(206.5, 39.6), Offset(225.2, 39.6),
        Offset(232.1, 43.6), Offset(250.2, 36.7), Offset(275.2, 32.3), Offset(298.5, 31.8), Offset(316.6, 27.3),
        Offset(327.7, 20.4), Offset(338.6, 16.1), Offset(336.1, 11.9), Offset(331.1, 7.0), Offset(338.0, 0.0),
        Offset(348.9, 0.0), Offset(363.9, 2.5), Offset(369.5, 0.0),
      ]),
      _polygon(const <Offset>[
        Offset(630.3, 33.4), Offset(632.5, 35.6), Offset(626.6, 34.9), Offset(619.9, 39.2), Offset(615.2, 43.6),
        Offset(615.8, 52.8), Offset(607.8, 55.6), Offset(605.1, 57.9), Offset(599.2, 61.7), Offset(588.9, 63.8),
        Offset(582.2, 67.2), Offset(581.7, 72.8), Offset(579.9, 74.2), Offset(586.0, 76.3), Offset(594.8, 81.9),
        Offset(592.6, 85.0), Offset(586.0, 85.8), Offset(575.0, 86.5), Offset(569.0, 92.2), Offset(562.0, 91.8),
        Offset(561.1, 93.0), Offset(553.5, 90.5), Offset(551.7, 92.9), Offset(547.1, 94.0), Offset(546.6, 91.6),
        Offset(542.6, 90.4), Offset(538.4, 88.4), Offset(542.6, 82.7), Offset(546.3, 81.2), Offset(544.9, 78.9),
        Offset(548.9, 71.9), Offset(547.8, 69.9), Offset(538.8, 68.5), Offset(531.5, 65.0), Offset(544.1, 56.8),
        Offset(561.2, 49.9), Offset(571.8, 40.8), Offset(579.2, 44.8), Offset(592.6, 45.3), Offset(590.2, 38.5),
        Offset(614.2, 33.0), Offset(620.3, 25.8),
      ]),
      _polygon(const <Offset>[
        Offset(594.8, 81.9), Offset(608.2, 97.0), Offset(612.0, 105.3), Offset(612.2, 120.1), Offset(606.3, 127.1),
        Offset(592.3, 129.6), Offset(579.9, 134.9), Offset(565.9, 136.0), Offset(564.2, 129.0), Offset(567.0, 119.4),
        Offset(560.2, 106.1), Offset(571.7, 103.9), Offset(561.1, 93.0), Offset(562.0, 91.8), Offset(569.0, 92.2),
        Offset(575.0, 86.5), Offset(586.0, 85.8), Offset(592.6, 85.0),
      ]),
      _polygon(const <Offset>[
        Offset(692.4, 139.1), Offset(694.3, 143.5), Offset(685.6, 151.3), Offset(679.2, 147.2), Offset(671.3, 150.1),
        Offset(667.2, 157.6), Offset(657.1, 154.0), Offset(657.2, 147.9), Offset(665.8, 140.3), Offset(674.6, 141.7),
        Offset(681.0, 136.3),
      ]),
      _polygon(const <Offset>[
        Offset(760.0, 132.4), Offset(759.6, 132.5), Offset(732.4, 133.3), Offset(710.3, 147.9), Offset(699.8, 143.0),
        Offset(699.2, 133.4), Offset(672.2, 136.2), Offset(653.9, 142.2), Offset(635.7, 142.5), Offset(651.4, 151.9),
        Offset(641.1, 173.7), Offset(631.1, 179.1), Offset(623.5, 174.1), Offset(627.4, 162.6), Offset(617.5, 158.8),
        Offset(611.2, 150.1), Offset(625.9, 146.1), Offset(634.0, 138.0), Offset(649.6, 131.4), Offset(661.0, 122.6),
        Offset(691.9, 118.8), Offset(708.5, 121.4), Offset(724.7, 98.7), Offset(735.0, 104.8), Offset(757.8, 92.0),
        Offset(760.0, 90.7),
      ]),
      _polygon(const <Offset>[
        Offset(492.9, 264.2), Offset(483.5, 284.7), Offset(476.9, 295.2), Offset(468.7, 284.4), Offset(467.0, 274.9),
        Offset(476.1, 262.3), Offset(488.5, 252.6), Offset(495.6, 256.4),
      ]),
      _polygon(const <Offset>[
        Offset(280.0, 300.6), Offset(259.3, 311.6), Offset(246.3, 323.7), Offset(242.9, 332.6), Offset(254.8, 346.1),
        Offset(269.3, 362.9), Offset(283.4, 370.8), Offset(292.8, 381.1), Offset(299.9, 404.8), Offset(297.8, 427.3),
        Offset(284.9, 435.8), Offset(267.1, 444.0), Offset(254.4, 454.7), Offset(235.1, 466.7), Offset(229.5, 458.4),
        Offset(233.8, 449.8), Offset(222.3, 442.5), Offset(235.8, 437.3), Offset(252.0, 436.4), Offset(245.2, 428.6),
        Offset(271.3, 418.8), Offset(273.2, 403.4), Offset(269.6, 394.8), Offset(272.4, 382.0), Offset(268.5, 373.0),
        Offset(256.8, 364.0), Offset(247.0, 352.8), Offset(234.1, 337.6), Offset(215.5, 329.9), Offset(220.0, 325.3),
        Offset(229.9, 322.0), Offset(223.9, 310.8), Offset(204.8, 310.7), Offset(197.8, 299.0), Offset(188.8, 288.9),
        Offset(197.1, 285.8), Offset(209.5, 285.8), Offset(224.5, 284.4), Offset(237.8, 277.5), Offset(245.2, 282.3),
        Offset(259.4, 284.7), Offset(257.0, 292.1), Offset(264.3, 297.3),
      ]),
      _polygon(const <Offset>[
        Offset(236.0, 393.9), Offset(241.1, 388.2), Offset(241.8, 377.3), Offset(229.2, 366.1), Offset(228.3, 353.5),
        Offset(216.5, 343.1), Offset(204.7, 342.2), Offset(201.6, 346.6), Offset(192.5, 347.0), Offset(187.9, 344.8),
        Offset(171.5, 352.4), Offset(171.2, 340.9), Offset(175.0, 327.4), Offset(164.5, 326.8), Offset(163.6, 319.1),
        Offset(156.9, 315.2), Offset(160.2, 310.4), Offset(173.4, 302.1), Offset(174.8, 305.1), Offset(183.1, 305.5),
        Offset(180.7, 290.8), Offset(188.8, 288.9), Offset(197.8, 299.0), Offset(204.8, 310.7), Offset(223.9, 310.8),
        Offset(229.9, 322.0), Offset(220.0, 325.3), Offset(215.5, 329.9), Offset(234.1, 337.6), Offset(247.0, 352.8),
        Offset(256.8, 364.0), Offset(268.5, 373.0), Offset(272.4, 382.0), Offset(269.6, 394.8), Offset(255.9, 390.1),
        Offset(248.8, 399.0),
      ]),
      _polygon(const <Offset>[
        Offset(195.2, 420.7), Offset(181.3, 414.8), Offset(168.0, 415.0), Offset(170.3, 405.0), Offset(156.6, 405.0),
        Offset(155.4, 419.1), Offset(147.0, 437.9), Offset(142.0, 449.2), Offset(143.0, 458.5), Offset(153.1, 458.9),
        Offset(159.4, 470.6), Offset(162.2, 481.7), Offset(170.9, 489.0), Offset(180.3, 490.5), Offset(188.3, 497.2),
        Offset(185.6, 500.0), Offset(172.3, 500.0), Offset(171.8, 497.4), Offset(159.1, 491.8), Offset(156.4, 494.0),
        Offset(150.3, 489.1), Offset(147.7, 482.8), Offset(139.4, 475.5), Offset(131.9, 469.5), Offset(129.3, 477.0),
        Offset(126.4, 469.9), Offset(128.1, 461.9), Offset(132.7, 449.6), Offset(140.2, 436.4), Offset(148.7, 424.5),
        Offset(142.6, 412.8), Offset(142.9, 406.8), Offset(141.1, 399.6), Offset(130.8, 389.5), Offset(127.1, 383.0),
        Offset(132.4, 380.7), Offset(138.1, 369.5), Offset(131.7, 361.1), Offset(121.9, 351.7), Offset(114.4, 340.4),
        Offset(120.9, 338.1), Offset(128.0, 324.3), Offset(139.0, 323.7), Offset(148.0, 318.1), Offset(156.9, 315.2),
        Offset(163.6, 319.1), Offset(164.5, 326.8), Offset(175.0, 327.4), Offset(171.2, 340.9), Offset(171.5, 352.4),
        Offset(187.9, 344.8), Offset(192.5, 347.0), Offset(201.6, 346.6), Offset(204.7, 342.2), Offset(216.5, 343.1),
        Offset(228.3, 353.5), Offset(229.2, 366.1), Offset(241.8, 377.3), Offset(241.1, 388.2), Offset(236.0, 393.9),
        Offset(221.5, 392.1), Offset(201.5, 394.5), Offset(191.5, 405.2),
      ]),
      _polygon(const <Offset>[
        Offset(209.3, 440.6), Offset(203.0, 433.9), Offset(195.2, 420.7), Offset(191.5, 405.2), Offset(201.5, 394.5),
        Offset(221.5, 392.1), Offset(236.0, 393.9), Offset(248.8, 399.0), Offset(255.9, 390.1), Offset(269.6, 394.8),
        Offset(273.2, 403.4), Offset(271.3, 418.8), Offset(245.2, 428.6), Offset(252.0, 436.4), Offset(235.8, 437.3),
        Offset(222.3, 442.5),
      ]),
      _polygon(const <Offset>[
        Offset(148.0, 318.1), Offset(139.0, 323.7), Offset(128.0, 324.3), Offset(120.9, 338.1), Offset(114.4, 340.4),
        Offset(121.9, 351.7), Offset(131.7, 361.1), Offset(138.1, 369.5), Offset(132.4, 380.7), Offset(127.1, 383.0),
        Offset(130.8, 389.5), Offset(141.1, 399.6), Offset(142.9, 406.8), Offset(142.6, 412.8), Offset(148.7, 424.5),
        Offset(140.2, 436.4), Offset(132.7, 449.6), Offset(131.2, 440.1), Offset(135.9, 430.2), Offset(130.7, 422.7),
        Offset(132.0, 408.7), Offset(125.7, 402.0), Offset(120.6, 386.7), Offset(117.8, 370.5), Offset(111.1, 359.9),
        Offset(100.9, 366.3), Offset(83.3, 375.5), Offset(74.6, 374.3), Offset(65.0, 371.3), Offset(70.3, 355.4),
        Offset(67.1, 343.4), Offset(54.9, 328.6), Offset(56.8, 324.0), Offset(47.7, 322.4), Offset(36.7, 311.9),
        Offset(35.7, 301.6), Offset(41.1, 303.5), Offset(41.5, 294.3), Offset(49.1, 291.3), Offset(47.5, 285.9),
        Offset(51.0, 281.5), Offset(51.6, 268.2), Offset(63.7, 271.1), Offset(70.6, 260.6), Offset(71.4, 254.3),
        Offset(80.0, 243.6), Offset(79.5, 236.2), Offset(99.6, 227.4), Offset(110.6, 229.7), Offset(109.4, 221.8),
        Offset(114.8, 219.5), Offset(113.6, 214.6), Offset(122.7, 213.6), Offset(127.9, 221.2), Offset(134.7, 224.2),
        Offset(135.1, 234.1), Offset(134.5, 244.6), Offset(119.8, 255.3), Offset(118.0, 270.5), Offset(134.3, 268.4),
        Offset(138.0, 280.2), Offset(147.8, 282.7), Offset(143.3, 293.4), Offset(154.8, 298.2), Offset(161.6, 300.5),
        Offset(172.9, 296.8), Offset(173.4, 302.1), Offset(160.2, 310.4), Offset(156.9, 315.2),
      ]),
      _polygon(const <Offset>[
        Offset(564.2, 469.0), Offset(565.8, 477.6), Offset(566.7, 484.8), Offset(561.4, 496.5), Offset(555.8, 483.4),
        Offset(548.5, 489.9), Offset(553.5, 499.4), Offset(553.0, 500.0), Offset(535.8, 500.0), Offset(530.8, 497.9),
        Offset(526.4, 488.7), Offset(531.1, 482.6), Offset(521.3, 476.5), Offset(516.4, 481.8), Offset(509.1, 481.3),
        Offset(497.7, 488.5), Offset(495.1, 484.7), Offset(501.2, 473.9), Offset(510.9, 470.3), Offset(519.4, 465.5),
        Offset(524.9, 471.3), Offset(536.7, 467.8), Offset(539.2, 462.0), Offset(550.2, 461.7), Offset(549.2, 451.8),
        Offset(561.8, 457.9), Offset(563.1, 464.3),
      ]),
      _polygon(const <Offset>[
        Offset(527.1, 445.1), Offset(521.5, 449.4), Offset(516.6, 457.5), Offset(511.8, 461.3), Offset(502.2, 452.4),
        Offset(505.4, 449.0), Offset(509.3, 445.4), Offset(511.0, 437.4), Offset(519.6, 436.7), Offset(517.1, 445.3),
        Offset(528.6, 432.9),
      ]),
      _polygon(const <Offset>[
        Offset(442.1, 457.5), Offset(421.5, 469.6), Offset(429.1, 460.7), Offset(440.3, 452.8), Offset(449.6, 443.9),
        Offset(457.7, 431.2), Offset(460.5, 441.6), Offset(450.3, 448.7),
      ]),
      _polygon(const <Offset>[
        Offset(494.5, 424.5), Offset(503.8, 428.4), Offset(513.7, 428.4), Offset(513.4, 433.8), Offset(506.2, 439.2),
        Offset(496.4, 443.1), Offset(495.8, 437.1), Offset(496.9, 430.6),
      ]),
      _polygon(const <Offset>[
        Offset(550.7, 421.0), Offset(555.0, 435.3), Offset(543.0, 431.9), Offset(543.4, 436.2), Offset(547.2, 444.1),
        Offset(539.8, 447.0), Offset(539.1, 438.0), Offset(534.5, 437.3), Offset(532.0, 429.5), Offset(541.2, 430.6),
        Offset(541.0, 425.7), Offset(531.5, 415.9), Offset(546.4, 416.2),
      ]),
      _polygon(const <Offset>[
        Offset(489.0, 409.4), Offset(484.9, 420.4), Offset(478.2, 414.0), Offset(470.3, 404.3), Offset(483.6, 404.7),
      ]),
      _polygon(const <Offset>[
        Offset(485.8, 339.7), Offset(495.4, 343.4), Offset(500.1, 340.0), Offset(501.6, 343.3), Offset(499.0, 348.6),
        Offset(504.3, 357.8), Offset(500.2, 368.4), Offset(491.1, 372.7), Offset(488.7, 383.0), Offset(492.1, 393.2),
        Offset(500.3, 394.6), Offset(507.2, 393.1), Offset(526.6, 400.2), Offset(525.1, 407.2), Offset(530.2, 410.3),
        Offset(528.5, 416.2), Offset(516.5, 409.9), Offset(510.7, 403.2), Offset(506.7, 407.9), Offset(496.9, 400.2),
        Offset(482.8, 402.1), Offset(475.1, 399.3), Offset(475.8, 394.0), Offset(480.7, 390.7), Offset(476.1, 387.7),
        Offset(474.1, 392.4), Offset(466.4, 385.0), Offset(464.1, 379.4), Offset(463.5, 367.1), Offset(469.7, 371.4),
        Offset(471.4, 351.3), Offset(476.4, 339.7),
      ]),
      _polygon(const <Offset>[
        Offset(171.8, 497.4), Offset(172.3, 500.0), Offset(185.6, 500.0), Offset(188.3, 497.2), Offset(191.9, 498.4),
        Offset(193.8, 500.0), Offset(159.8, 500.0), Offset(159.9, 499.5), Offset(156.4, 494.0), Offset(159.1, 491.8),
      ]),
      _polygon(const <Offset>[
        Offset(404.2, 500.0), Offset(406.7, 498.2), Offset(414.5, 488.1), Offset(420.8, 488.1), Offset(428.8, 494.6),
        Offset(429.4, 500.0),
      ]),
    ];
    for (final country in countries) {
      canvas.drawPath(country, land);
      canvas.drawPath(country, edge);
    }

    _label(canvas, 'CHINA', const Offset(390, 160), size: 16);
    _label(canvas, 'KOREA', const Offset(568, 72), size: 14);
    _label(canvas, 'JAPAN', const Offset(675, 130), size: 13);
    _label(canvas, 'THAILAND', const Offset(135, 372), size: 13);
    _label(canvas, 'LAOS', const Offset(186, 325), size: 13);
    _label(canvas, 'VIETNAM', const Offset(263, 365), size: 13);
    final land = _landPath(), sea = _seaPath(), air = _airPath();
    _drawRoute(canvas, land, const Color(0xFF2F80ED), true);
    _drawRoute(canvas, sea, const Color(0xFFEF3F48), mode == CargoTrackingMode.sea);
    _drawRoute(canvas, air, const Color(0xFFFFAD32), mode == CargoTrackingMode.air);

    final node = Paint()..color = Colors.white;
    final nodeEdge = Paint()
      ..color = const Color(0xFF2F80ED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final point in const [
      Offset(563, 106),
      Offset(557, 93),
      Offset(169, 409),
      Offset(195, 346),
    ]) {
      canvas.drawCircle(point, 5, node);
      canvas.drawCircle(point, 5, nodeEdge);
    }
    _drawWarehouse(canvas, const Offset(575, 96));
    _drawWarehouse(canvas, const Offset(207, 337));
    _label(
      canvas,
      CargoTrackingLabels.location(language, 'incheonCenter'),
      const Offset(622, 82),
      size: 15,
      align: TextAlign.right,
    );
    _label(
      canvas,
      CargoTrackingLabels.location(language, 'lkCenter'),
      const Offset(232, 337),
      size: 15,
    );
    _drawVehicle(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CargoRoutePainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.progress != progress ||
      oldDelegate.language != language;
}
