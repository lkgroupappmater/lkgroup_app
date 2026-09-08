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
      CargoTracking.phase(schedule, now: DateTime(2026, 9, 8)),
      CargoTrackingPhase.arrived,
    );
    expect(
      CargoTracking.phase(schedule, now: DateTime(2026, 9, 10)),
      CargoTrackingPhase.dispatching,
    );
    schedule['estimated_arrival_date'] = '2026-09-12';
    expect(
      CargoTracking.phase(schedule, now: DateTime(2026, 9, 10)),
      CargoTrackingPhase.moving,
    );
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
