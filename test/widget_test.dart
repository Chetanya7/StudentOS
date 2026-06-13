import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studentos/main.dart';

void main() {
  const notificationChannel = MethodChannel('studentos/notification_service');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          if (call.method == 'shouldAsk') {
            return false;
          }

          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
  });

  testWidgets('shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentOS());

    expect(find.text('StudentOS'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
