import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/route_catalog.dart';

void main() {
  test('server order cannot reorder the eleven standard routes', () {
    const expected = ['kr_la_sea','kr_la_air','la_kr_air_exp','la_th_land',
      'th_la_land','la_vn_land','vn_la_land','la_ch_land','ch_la_land',
      'la_kh_land','kh_la_land'];
    final rows = expected.reversed.map((key) => <String, dynamic>{
      'route_key': key, 'display_name': key, 'status': 'active',
    }).toList();
    rows.insert(0, {'route_key':'custom','display_name':'Custom','status':'active'});
    rows.add({'route_key':'deleted','display_name':'Deleted','status':'deleted'});
    RouteCatalog.applyDatabaseDefinitions(rows);
    expect(RouteCatalog.definitions.map((r) => r.routeKey).toList(), [...expected, 'custom']);
  });
}
