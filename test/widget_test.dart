import 'package:flutter_test/flutter_test.dart';

import 'package:anima/main.dart';
import 'package:anima/services/api_key_service.dart';

void main() {
  testWidgets('Anima home screen shows welcome and settings entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(AnimaApp(apiKeyService: ApiKeyService()));

    expect(find.text('Welcome to Anima'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
