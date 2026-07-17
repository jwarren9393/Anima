# Anima

Private, personal AI character chat app built with Flutter.
Talks to the [NanoGPT](https://nano-gpt.com) API for replies.

**Platforms:** Android (primary), Windows, Linux  
**Not published** to any app store — for personal use only.

---

## For humans (you)

### What this app is

Anima is your private place to chat with AI characters on your own devices.
Your NanoGPT API key is typed into Settings inside the app and stored in the
device's secure vault — it is never put in project files or GitHub.

### What you need on this computer

1. Flutter SDK (already at `~/development/flutter`)
2. Later: Android Studio / Android SDK to put the app on your phone
3. A NanoGPT API key from https://nano-gpt.com

### Quick commands

```bash
# Make sure Flutter is on your PATH for this terminal
export PATH="$HOME/development/flutter/bin:$PATH"

# Check tooling
flutter doctor

# Get packages (if needed)
flutter pub get

# Run on Linux desktop (once Linux build tools are installed)
flutter run -d linux

# Run on a connected Android phone (once Android SDK is set up)
flutter run -d android
```

### Saving your API key (safe)

1. Open the app
2. Tap **Settings** (gear icon) or **Open Settings**
3. Paste your NanoGPT key and tap **Save API key**

That key lives only on that device. It will not appear in this GitHub repo.

---

## For AI agents

**Read and update [`AGENTS.md`](AGENTS.md) every session.**  
That file is the living build status: what exists, what's next, and rules.

---

## Project layout (simple)

```
lib/
  main.dart                 # App entry + theme
  screens/
    chat_screen.dart        # Home / chat placeholder
    settings_screen.dart    # Secure API key input
  services/
    api_key_service.dart    # Secure storage for the NanoGPT key
    nanogpt_service.dart    # NanoGPT HTTP chat client (starter)
```

---

## Security rules

- Never commit API keys, `.env` files, or keystore passwords
- Never hard-code secrets in Dart source
- Use `ApiKeyService` / Settings screen for the NanoGPT key
