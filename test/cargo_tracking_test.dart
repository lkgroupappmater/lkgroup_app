import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/cargo_tracking.dart';

void main() {
  test('cargo route, year and voyage match the registered schedule', () {
    final cargo = <String, dynamic>{
      'route': '한국->라오스 해상',
      'shipment_year': '2026년',
      'voyage': 'V09항차',
    };
    final schedule = <String, dynamic>{
      'route': 'Kor-Lao Sea',
      'route_category': 'sea',
      'year': 2026,
      'voyage': '09',
    };

    expect(CargoTracking.matches(cargo, schedule), isTrue);
    expect(
      CargoTracking.matches(cargo, {...schedule, 'route': 'Laos->Korea Sea'}),
      isFalse,
    );
  });

  test('arrival phase changes on ETA and two calendar days later', () {
    final schedule = <String, dynamic>{
      'route': '한국->라오스 해상',
      'booking_close_date': '2026-09-01',
      'estimated_arrival_date': '2026-09-08',
    };

    expect(
      CargoTracking.phase(schedule, now: DateTime.utc(2026, 9, 8)),
      CargoTrackingPhase.arrived,
    );
    expect(
      CargoTracking.phase(schedule, now: DateTime.utc(2026, 9, 10)),
      CargoTrackingPhase.dispatching,
    );
    schedule['estimated_arrival_date'] = '2026-09-12';
    expect(
      CargoTracking.phase(schedule, now: DateTime.utc(2026, 9, 10)),
      CargoTrackingPhase.moving,
    );
  });

  test('air changes at exactly 16:00 Laos, including a saved arrived status', () {
    for (final status in ['', 'arrived', '도착', '도착완료']) {
      final schedule = <String, dynamic>{
        'route': '한국->라오스 항공',
        'estimated_arrival_date': '2026-10-03',
        'status': status,
      };
      expect(CargoTracking.phase(schedule,
          now: DateTime.parse('2026-10-03T08:59:59.999Z')),
          CargoTrackingPhase.arrived);
      expect(CargoTracking.phase(schedule,
          now: DateTime.parse('2026-10-03T09:00:00Z')),
          CargoTrackingPhase.dispatching);
      expect(CargoTracking.phase(schedule,
          now: DateTime.parse('2026-10-04T07:00:00Z')),
          CargoTrackingPhase.dispatching);
    }
  });

  test('sea changes at Laos midnight two calendar days after ETA', () {
    final schedule = <String, dynamic>{
      'route_category': 'sea',
      'estimated_arrival_date': '2026-10-31',
      'status': 'arrived',
    };
    expect(CargoTracking.phase(schedule,
        now: DateTime.parse('2026-11-01T16:59:59.999Z')),
        CargoTrackingPhase.arrived);
    expect(CargoTracking.phase(schedule,
        now: DateTime.parse('2026-11-01T17:00:00Z')),
        CargoTrackingPhase.dispatching);
  });

  test('arrival and a postponed ETA follow Laos dates, not stale arrived text', () {
    final schedule = <String, dynamic>{
      'route_category': 'air',
      'booking_close_date': '2026-10-01',
      'estimated_arrival_date': '2026-10-03',
      'tracking_status': 'arrived',
    };
    expect(CargoTracking.phase(schedule,
        now: DateTime.parse('2026-10-02T16:59:59.999Z')),
        CargoTrackingPhase.moving);
    expect(CargoTracking.phase(schedule,
        now: DateTime.parse('2026-10-02T17:00:00Z')),
        CargoTrackingPhase.arrived);
    schedule['estimated_arrival_date'] = '2026-10-05';
    final now = DateTime.parse('2026-10-03T10:00:00Z');
    expect(CargoTracking.phase(schedule, now: now), CargoTrackingPhase.moving);
    expect(CargoTracking.progress(schedule, now: now), lessThan(1));
  });

  test('timestamp ETA and explicit time zones use the same Laos calendar day', () {
    for (final eta in ['2026-10-03T12:00:00',
      '2026-10-02T18:00:00Z', '2026-10-03T03:00:00+09:00']) {
      final schedule = <String, dynamic>{'route': 'LKA', 'eta': eta};
      for (final now in ['2026-10-03T09:00:00Z',
        '2026-10-03T18:00:00+09:00', '2026-10-03T02:00:00-07:00']) {
        expect(CargoTracking.phase(schedule, now: DateTime.parse(now)),
            CargoTrackingPhase.dispatching);
      }
    }
  });

  test('manual dispatch is preserved and missing or invalid ETA is safe', () {
    final now = DateTime.utc(2026, 10, 3);
    expect(CargoTracking.phase({'status': '출고중',
      'estimated_arrival_date': '2026-10-10'}, now: now),
      CargoTrackingPhase.dispatching);
    for (final eta in [null, '', 'invalid', '2026-02-30']) {
      expect(CargoTracking.phase({'eta': eta}, now: now),
          CargoTrackingPhase.moving);
      expect(CargoTracking.phase({'eta': eta, 'status': 'arrived'}, now: now),
          CargoTrackingPhase.arrived);
    }
  });

  test('sea cargo uses the vessel leg at the midpoint of its schedule', () {
    final schedule = <String, dynamic>{
      'route': '한국->라오스 해상',
      'booking_close_date': '2026-09-09T00:00:00Z',
      'estimated_arrival_date': '2026-09-29T00:00:00Z',
    };
    final progress = CargoTracking.progress(
      schedule,
      now: DateTime.parse('2026-09-19T00:00:00Z').toLocal(),
    );
    final leg = CargoTracking.currentLeg(CargoTrackingMode.sea, progress);

    expect(progress, closeTo(.5, .001));
    expect(leg.vehicle, CargoTrackingVehicle.ship);
    expect(leg.from, 'incheonPort');
    expect(leg.to, 'laemChabang');
  });
}
