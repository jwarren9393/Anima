import 'package:flutter/material.dart';

import '../services/api_key_service.dart';
import 'settings_screen.dart';

/// Placeholder home screen for chatting with your AI character.
///
/// Real chat (bubbles, NanoGPT calls, characters) comes in later phases.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.apiKeyService});

  final ApiKeyService apiKeyService;

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(apiKeyService: apiKeyService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anima'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: .center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to Anima',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: .center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your private AI character chat.\n'
                'Start by opening Settings and saving your NanoGPT API key.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: .center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.key),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
