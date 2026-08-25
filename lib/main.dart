import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rkqwzxfcnciptnwesfbr.supabase.co',
    anonKey: 'sb_publishable_O1kCnQpkg9SMDVcBSrOW5g_qzASvJCJ',
  );

  runApp(const CargoFlowApp());
}
