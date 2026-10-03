import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/notification_alert.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 tearDown((){debugDefaultTargetPlatformOverride=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,null);});
 test('existing Android platform bridge plays sound and vibrates',()async{
  debugDefaultTargetPlatformOverride=TargetPlatform.android;
  final calls=<MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,(call)async{calls.add(call);return null;});
  await NotificationAlert.play();
  expect(calls.map((c)=>c.method),['SystemSound.play','HapticFeedback.vibrate']);
  expect(calls.first.arguments,'SystemSoundType.click');
 });
 test('device audio failure does not prevent visible notification flow',()async{
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,(call)async{throw PlatformException(code:'disabled');});
  await expectLater(NotificationAlert.play(),completes);
 });
}
