# Connecto 📱💻

Connecto is a secure, cross-platform companion application that seamlessly bridges your Android smartphone and your macOS desktop. By operating entirely over your local network, it brings your phone's contacts, live caller ID, and connection status directly to your Mac without relying on third-party cloud servers.

## ✨ Features

- **🔒 Secure QR Code Pairing:** Instantly and securely pair your macOS desktop with your Android phone using a built-in QR code scanner.
- **📇 Real-time Contacts Sync:** Automatically mirrors your phone's contact book to your Mac. Includes an A-Z fast-scroll index, sticky headers, instant search, and a persistent "Favorites" list.
- **📞 Desktop Caller ID & Popups:** Receive beautiful, native-feeling incoming and outgoing call popups right on your Mac monitor. Caller IDs are instantly matched against your synced contacts.
- **🟢 Live Status Monitoring:** A sleek, split-pane desktop dashboard that provides real-time insights into your phone's connectivity state (Connected, Paused, or Offline).
- **🛡️ Privacy First:** All communication happens over a local Node.js WebSocket relay server. Your contacts and call data never leave your local Wi-Fi network.

## 🏗️ Architecture

Connecto is built with a unified Flutter codebase for both platforms, backed by a local Node.js relay server:

1. **Android Companion App:** Acts as the data provider. It runs a robust background foreground service (`PhoneStateService.kt`) that monitors Android telephony events and reads the local contact database.
2. **macOS Desktop Client:** Acts as the consumer and UI surface. It provides a polished, highly-responsive dark-mode interface optimized for keyboard/mouse interaction.
3. **Local WebSocket Relay (`server.js`):** A lightweight Node.js server that brokers real-time, low-latency WebSocket messages (contacts sync, call state, pairing handshakes) between the Mac and the phone.

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable)
- Node.js (for the relay server)
- An Android device (Android 10+)
- A macOS computer

### 1. Start the Relay Server
Navigate to the root directory and start the local WebSocket relay:
```bash
node server.js
```

### 2. Run the macOS Desktop App
Open a new terminal, ensure you are in the project root, and run:
```bash
flutter run -d macos
```

### 3. Run the Android Companion App
Connect your Android phone via USB or Wireless Debugging and run:
```bash
flutter run -d <your-android-device-id>
```

### 4. Pair Devices
1. The macOS app will display a QR code on the first launch.
2. Open the Pakku Connect app on your Android phone and scan the QR code to pair the devices.
3. Once paired, the Android app will transition to a background service, and the macOS app will open the main dashboard and sync your contacts.

## 🛠️ Tech Stack
- **UI Framework:** Flutter / Dart
- **Backend Relay:** Node.js, WebSockets (`ws`)
- **Native Android:** Kotlin, Android Telephony API, NotificationListenerService
- **Persistence:** SharedPreferences
