import 'package:flutter/material.dart';
import 'supabase_config.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  runApp(const CargoFlowApp());
}
