import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

const _supabaseUrl = 'https://rkqwzxfcnciptnwesfbr.supabase.co';
const _supabasePublishableKey = 'sb_publishable_O1kCnQpk9SMDVcBSrOW5g_qzASvJQC';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );

    // 연결 테스트용 코드입니다.
    // RLS 정책이나 테이블이 아직 준비되지 않아도 앱은 계속 실행됩니다.
    try {
      final data = await Supabase.instance.client
          .from('shipments')
          .select('shipment_no, consignee_name, status')
          .limit(5);

      debugPrint('DB 연결 OK → $data');
    } catch (error, stackTrace) {
      debugPrint('DB 조회 테스트 실패 → $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  } catch (error, stackTrace) {
    // Supabase 초기화 실패 시에도 앱 화면은 실행되도록 합니다.
    // 실제 DB 기능을 사용할 때는 이 로그의 원인을 확인해야 합니다.
    debugPrint('Supabase 초기화 실패 → $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const CargoFlowApp());
}
