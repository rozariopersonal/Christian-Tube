# ChristianTube Mobile App 📱✝️

ChristianTube is an open-source Flutter mobile application designed to stream high-quality Christian videos, sermons, praise & worship music, devotional watch plans, and vertical shorts.

[![Releases](https://img.shields.io/github/v/release/rozariopersonal/Christian-Tube-Releases?label=Latest%20Release)](https://github.com/rozariopersonal/Christian-Tube-Releases/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Android-green.svg)](https://github.com/rozariopersonal/Christian-Tube-Releases)

---

## 🌟 Key Features

- 🎥 **Video Feed**: Filter by spiritual categories (Worship, Sermons, Testimonies, Bible Study, Kids).
- ⚡ **Christian Shorts**: High-framerate vertical video feed for devotionals and clips.
- 📺 **Rich Video Player**: Multi-quality direct streaming via `youtube_explode_dart` with `youtube_player_iframe` fallback.
- ✂️ **Create Clips/Shorts**: Extract memorable segments from full-length sermons directly in-app.
- 📖 **Devotion & Watch Plans**: Set daily spiritual study targets with streak tracking and reminders.
- 🌐 **Multi-Language Support**: English, Hindi (हिन्दी), Tamil (தமிழ்), Telugu (తెలుగు), Kannada (ಕನ್ನಡ), and Malayalam (മലയാളം).
- 🔄 **In-App Self Updates**: Automatic OTA notification & install via GitHub Releases.
- 🎨 **Material 3 Dynamic Themes**: Seamless Dark and Light theme toggle.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (v3.22.x or higher)
- Android Studio / VS Code with Flutter extension
- Java 17

### Installation
```bash
# 1. Clone the repository
git clone https://github.com/rozariopersonal/Christian-Tube.git
cd Christian-Tube

# 2. Install dependencies
flutter pub get

# 3. Run on connected device or emulator
flutter run
```

---

## 🤖 Automated CI/CD Releases

This repository includes a GitHub Actions workflow (`.github/workflows/release.yml`) configured to automatically build and publish release APKs to [Christian-Tube-Releases](https://github.com/rozariopersonal/Christian-Tube-Releases).

To publish a new version:
```bash
git tag v1.28.0
git push origin v1.28.0
```
