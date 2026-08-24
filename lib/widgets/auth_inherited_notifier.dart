// lib/controllers/auth_inherited_notifier.dart
//
// provider 없이 위젯 트리에 AuthController 를 주입하기 위한
// InheritedNotifier 래퍼입니다.

import 'package:flutter/widgets.dart';
import '../controllers/auth_controller.dart';

class AuthControllerScope extends InheritedNotifier<AuthController> {
  const AuthControllerScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AuthControllerScope>();
    assert(scope != null, 'AuthControllerScope를 찾을 수 없습니다.');
    return scope!.notifier!;
  }

  /// rebuild 없이 현재 값만 읽을 때 사용
  static AuthController read(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<AuthControllerScope>();
    assert(scope != null, 'AuthControllerScope를 찾을 수 없습니다.');
    return scope!.notifier!;
  }
}

