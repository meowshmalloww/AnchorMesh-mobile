# AnchorMesh

**Store-and-Forward Offline Mesh Network for Disaster Rescue**

> "Even if you don't need rescue, hold out the phone so SOS messages can pass through!"

AnchorMesh turns every smartphone into a rescue node during natural disasters when cell service and Wi-Fi fail. Using BLE mesh networking, it creates a decentralized communication system where **everyone is a carrier**.

---

## Features

### SOS System
- **Red (Critical)**: Trapped, immediate danger
- **Yellow (Injured)**: Need medical aid or supplies
- **Green (Safe)**: Broadcasts "I AM SAFE" status

Users select from pre-defined status codes only - no manual text entry - ensuring data integrity and minimal packet size.

### Mesh Network
- **Store-and-Forward**: Packets are stored locally and forwarded when other devices come in range
- **Epidemic Routing**: Encrypted packets spread through the network automatically
- **Cloud Sync**: When internet returns, packets upload to the rescue server
- **Echo Feedback**: Notifies you when your signal has been relayed by others

### Offline Utilities
- **Signal Locator**: RSSI-based "hot/cold" meter to locate victims
- **Ultrasonic SOS**: High-frequency audio (17-20kHz) for close-range transfer
- **Compass**: Magnetic heading navigation
- **Offline Maps**: OpenStreetMap tile caching
- **Strobe Light**: Flashlight signaling

### Smart Activation
- Auto-activates mesh mode after 3 consecutive failed internet pings
- Background disaster monitoring via USGS/NOAA APIs
- Boot recovery on Android (auto-restarts listener after reboot)

---

## Technical Specs

### BLE Configuration
| Spec | Value |
|------|-------|
| Range | 30-100m (indoor), up to 400m (open air) |
| MTU (Android) | Up to 514 bytes |
| MTU (iOS) | 185-527 bytes (system managed) |
| Connections | 3-7 simultaneous |

### Packet Format (25 bytes)
| Bytes | Field | Size | Details |
|-------|-------|------|---------|
| 0-1 | Header | 2B | `0xFFFF` (handshake) |
| 2-5 | User ID | 4B | Random 32-bit integer |
| 6-7 | Sequence | 2B | Increment counter |
| 8-11 | Latitude | 4B | Scaled integer (`lat * 10^7`) |
| 12-15 | Longitude | 4B | Scaled integer (`lon * 10^7`) |
| 16 | Status | 1B | `0x00`=Safe, `0x01`=SOS, etc. |
| 17-20 | Timestamp | 4B | Unix epoch seconds |

GPS coordinates are compressed to integers for ~1.1cm precision.

### Battery Modes
| Mode | Scan | Sleep | Est. Life |
|------|------|-------|-----------|
| SOS Active | Always | None | 6-8 hrs |
| Bridge (Default) | 30s | 30s | 12+ hrs |
| Battery Saver | 5s | 55s | 24+ hrs |
| Peace | Off | Off | Normal |

---

## Getting Started

### Prerequisites
- Flutter SDK 3.10.3+
- Xcode (for iOS)
- Android Studio (for Android)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/anchormesh.git
cd anchormesh

# Install dependencies
flutter pub get

# Run on device (BLE requires physical device)
flutter run
```

### iOS Setup
1. Open `ios/Runner.xcworkspace` in Xcode
2. Set your development team in Signing & Capabilities
3. Enable Background Modes: "Uses Bluetooth LE accessories" and "Acts as a Bluetooth LE accessory"
4. Build and run on a physical device

### Android Setup
1. Ensure `minSdkVersion` is 21+ in `android/app/build.gradle.kts`
2. Build and run on a physical device

---

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── home_screen.dart          # Main navigation scaffold
├── config/
│   └── api_config.dart       # API endpoints configuration
├── models/
│   ├── sos_packet.dart       # SOS packet data model
│   ├── sos_status.dart       # Status enums
│   ├── ble_models.dart       # BLE data models
│   └── disaster_event.dart   # Disaster event model
├── pages/
│   ├── home_page.dart        # Dashboard
│   ├── map_page.dart         # Map view
│   ├── sos_page.dart         # SOS controls
│   ├── settings_page.dart    # App settings
│   ├── offline_utility_page.dart
│   ├── signal_locator_page.dart
│   └── onboarding_page.dart
├── services/
│   ├── ble_service.dart      # BLE mesh operations
│   ├── packet_store.dart     # Local SQLite storage
│   ├── supabase_service.dart # Cloud sync
│   ├── connectivity_service.dart
│   ├── notification_service.dart
│   ├── disaster_service.dart
│   └── platform_service.dart
├── widgets/
│   ├── sos_button.dart
│   ├── proximity_radar.dart
│   └── ...
└── theme/
    └── resq_theme.dart
```

---

## Platform Implementation

### iOS
- Foreground: `isIdleTimerDisabled = true` keeps radio active
- Background: BLE Background Mode with Service UUID scanning
- Overflow Area advertising for background broadcasting
- Low Power Mode warning (cannot be overridden)

### Android
- Requests `ACTION_IGNORE_BATTERY_OPTIMIZATIONS`
- Boot Receiver for automatic service restart
- Dual-mode advertising (Legacy 4.x / Extended 5.0+)
- Foreground service for persistent operation

---

## Dependencies

- **flutter_map** - OpenStreetMap integration
- **geolocator** - GPS location
- **sqflite** - Local packet storage
- **supabase_flutter** - Cloud sync
- **just_audio** - Ultrasonic SOS
- **vibration** - Haptic feedback
- **compassx** - Magnetic compass
- **torch_light** - Flashlight control
- **flutter_local_notifications** - SOS alerts

---

## Built For

Earthquakes, tsunamis, volcanic eruptions, floods, hurricanes, tornadoes, wildfires, and any scenario where traditional communication infrastructure fails.

---

## License

This software is provided for **hackathon evaluation only**. See [LICENSE](LICENSE) for details.

Copyright (c) 2026 ResQ Team. All Rights Reserved.

---

*2025 Alameda County Hackathon*
