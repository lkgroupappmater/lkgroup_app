import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/services/freight_policy_service.dart';

void main() {
  for (final minimum in [1.5, 14.0]) {
    final policy = FreightPolicy(routeKey: 'test', minimumCharge: minimum,
      volumetricFactor: .00022, tiers: [FreightRateTier(minWeightKg: 0, ratePerKg: minimum)], sourceNote: '');
    test('minimum $minimum applies per cargo at sub-kilogram weights', () {
      for (final quantity in [1.0, 2.0, 10.0]) {
        for (final weight in [.22, .5, .999, 1.0]) {
          expect(policy.grossAmount(weight * quantity, minimum, quantity), minimum * quantity);
        }
      }
    });
    test('minimum $minimum preserves larger, empty and overridden amounts', () {
      expect(policy.grossAmount(4, minimum, 2), minimum * 4);
      expect(policy.grossAmount(0, minimum, 2), 0);
      expect(policy.grossAmount(1, minimum / 2, 2), minimum * 2);
      expect(policy.grossAmount(1, 0, 2), 0);
    });
  }
}
