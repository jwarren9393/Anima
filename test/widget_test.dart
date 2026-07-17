import 'package:flutter_test/flutter_test.dart';

import 'package:anima/main.dart';
import 'package:anima/services/api_key_service.dart';
import 'package:anima/services/nanogpt_service.dart';
import 'package:anima/services/settings_service.dart';

void main() {
  testWidgets('Anima chat screen shows empty state and composer', (
    WidgetTester tester,
  ) async {
    final apiKeyService = ApiKeyService();
    final settingsService = SettingsService();
    final nanoGptService = NanoGptService(apiKeyService: apiKeyService);

    await tester.pumpWidget(
      AnimaApp(
        apiKeyService: apiKeyService,
        settingsService: settingsService,
        nanoGptService: nanoGptService,
      ),
    );
    await tester.pump(); // allow async key check to schedule
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Start chatting'), findsOneWidget);
    expect(find.text('Type a message…'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
