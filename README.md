# Anima

Private, personal AI character chat app built with Flutter.
Talks to the [NanoGPT](https://nano-gpt.com) API for replies.

**Platforms:** Android (primary), Windows, Linux  
**Not published** to any app store — for personal use only.  
**Repo:** https://github.com/jwarren9393/Anima (private)

---

## For humans (you)

### What this app is

Anima is your private place to chat with AI characters on your own devices.
Your NanoGPT API key is typed into Settings inside the app and stored in the
device's secure vault — it is never put in project files or GitHub.

### What you need on this computer

1. Flutter SDK at `~/development/flutter`
2. JDK 17 at `~/development/jdk-17` and Android SDK at `~/Android/Sdk` (Phase 1 — installed)
3. A NanoGPT API key from https://nano-gpt.com
4. An Android phone with USB debugging (to install the app)

### Quick commands

```bash
# Load the toolchain (new terminals should get this from ~/.bashrc)
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$HOME/.local/bin:$PATH"

# Check tooling
flutter doctor

# See connected phones
adb devices
flutter devices

# Run on a connected Android phone
cd /run/media/jakwan/JaKwanSSD/AI/Anima
flutter run
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
  models/
    chat_message.dart       # One chat bubble
  screens/
    chat_screen.dart        # Chat with NanoGPT
    settings_screen.dart    # API key + model
  services/
    api_key_service.dart    # Secure storage for the NanoGPT key
    settings_service.dart   # Saved model name
    nanogpt_service.dart    # Talks to NanoGPT over the internet
```

---

## Security rules

- Never commit API keys, `.env` files, or keystore passwords
- Never hard-code secrets in Dart source
- Use `ApiKeyService` / Settings screen for the NanoGPT key
