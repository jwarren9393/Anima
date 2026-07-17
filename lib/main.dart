import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/api_key_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AnimaApp(apiKeyService: ApiKeyService()));
}

class AnimaApp extends StatelessWidget {
  const AnimaApp({super.key, required this.apiKeyService});

  final ApiKeyService apiKeyService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anima',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: const Color(0xFF2F6F6A),
          brightness: .light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: const Color(0xFF2F6F6A),
          brightness: .dark,
        ),
        useMaterial3: true,
      ),
      themeMode: .system,
      home: ChatScreen(apiKeyService: apiKeyService),
    );
  }
}
