// ============================================================
//  lib/supabase_config.dart
//  CargoFlow · lkgroup_app
//
//  [ 패키지 설치 ]
//  pubspec.yaml 의 dependencies 에 아래 한 줄을 추가한 뒤
//  `flutter pub get` 을 실행하세요.
//
//    supabase_flutter: ^2.8.4   # 또는 최신 2.x 버전
//
//  [ 사용 방법 – main.dart ]
//
//    import 'package:flutter/material.dart';
//    import 'supabase_config.dart';
//
//    Future<void> main() async {
//      WidgetsFlutterBinding.ensureInitialized();
//      await SupabaseConfig.initialize();   // ← 반드시 runApp() 전에 호출
//      runApp(const MyApp());
//    }
//
//  이후 어디서든:
//    final rows = await SupabaseConfig.client
//        .from('shipments')
//        .select()
//        .execute();
//
//  [ 교체해야 할 두 값 ]
//
//  1) _kProjectUrl
//     Supabase 대시보드 → 프로젝트 선택 → Settings → API
//     "Project URL" 항목의 값 (https://xxxxxxxxxx.supabase.co)
//
//  2) _kAnonKey
//     같은 페이지의 "Project API Keys" 섹션에서
//     "anon  public" (publishable) 키 값
//     ──────────────────────────────────────────────────────
//     ⚠️  절대로 service_role 키를 여기에 넣지 마세요!
//         service_role 키는 RLS(행 수준 보안)를 완전히 우회하며
//         데이터베이스 비밀번호도 마찬가지로 클라이언트 코드에
//         포함시키면 안 됩니다.
//     ──────────────────────────────────────────────────────
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';

// ── ① 여기만 수정하세요 ────────────────────────────────────────

/// Supabase 대시보드 → Settings → API → Project URL
const String _kProjectUrl = 'https://rkqwzxfcnciptnwesfbr.supabase.co';
// 예시: 'https://abcdefghijklmnop.supabase.co'

/// Supabase 대시보드 → Settings → API → anon public (publishable) key
/// ⚠️  service_role 키 절대 사용 금지
const String _kAnonKey = 'sb_publishable_O1kCnQpkg9SMDVcBSrOW5g_qzASvJCJ';
// 예시: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'

// ── ② 아래는 수정하지 마세요 ──────────────────────────────────

/// Supabase 연결 설정 및 클라이언트 접근을 담당하는 설정 클래스.
///
/// 사용 예:
/// ```dart
/// await SupabaseConfig.initialize();      // main() 에서 한 번만 호출
/// final client = SupabaseConfig.client;   // 이후 어디서든 접근 가능
///
