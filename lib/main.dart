import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rkqwzxfcnciptnwesfbr.supabase.co',
    anonKey: 'sb_publishable_O1kCnQpkg9SMDVcBSrOW5g_qzASvJCJ',
  );

  // 연결 확인용 임시 코드
  try {
    final data = await Supabase.instance.client
        .from('shipments')
        .select('shipment_no, consignee_name, status')
        .limit(5);

    debugPrint('DB 연결 OK → $data');
  } catch (error) {
    debugPrint('DB 연결 실패 → $error');
  }

  runApp(const CargoFlowApp());
}
