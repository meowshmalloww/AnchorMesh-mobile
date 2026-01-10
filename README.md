# ResQ - Offline Disaster Resilience 🛟
> *Stay Connected When It Matters Most.*

**ResQ** is a decentralized, offline-first disaster communication platform designed to keep communities connected even when cellular networks fail. Built with **Flutter**, it creates an ad-hoc mesh network between devices using **Bluetooth Low Energy (BLE)** and **Ultrasonic** sound waves to propagate SOS signals and critical alerts.

---

## 🚀 Key Features

### 📡 Offline Mesh Network
- **BLE Mesh**: Uses both **Legacy (BLE 4.0)** and **Extended (BLE 5.0)** advertising to maximize compatibility and range.
- **Ultrasonic SOS**: Transmits emergency data via high-frequency sound waves for devices without BLE or as a redundant channel.
- **Relay System**: Every phone acts as a node, relaying active SOS packets to extend the network reach automatically.

### 🗺️ Disaster Intelligence
- **Real-Time Map**: Aggregates data from **USGS (Earthquakes), NOAA (Weather), and GDACS (Global Disasters)**.
- **Offline Maps**: Pre-download critical map tiles (OpenStreetMap) for use without internet.
- **Danger Zones**: Visualizes impact radius for earthquakes, fires, and floods dynamically.
- **Smart Filtering**: Auto-filters alerts based on your proximity (200km radius) to reduce panic fatigue.

### 🔋 Survival Utilities
- **Battery Optimization**: Intelligent duty cycling for BLE scanning to last days in emergencies.
- **Compass Navigation**: Built-in compass for wayfinding when GPS maps are unavailable.
- **Signal Locator**: Detects signal strength (RSSI) of nearby mesh nodes to help locate survivors.

### ☁️ Hybrid Connectivity
- **Cloud Sync**: Automatically syncs critical data to Supabase when intermittent internet is detected.
- **Weather Fallback**: Checks multiple APIs (OpenWeatherMap + Standard Forecast) to ensure weather data availability.

---

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (iOS & Android)
- **Language**: Dart 3
- **Hardware Comms**:
  - `flutter_blue_plus` (BLE)
  - `flutter_quiet` (Ultrasonic Data Transmission)
- **Mapping**:
  - `flutter_map` (OpenStreetMap)
  - `latlong2`
- **Backend / Sync**: Supabase
- **State Management**: Provider / Streams

---

## ⚡ Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.10+)
- Android device (API 21+) or iOS device (iOS 12+) for BLE features.

### Installation

1. **Clone the repo**
   ```bash
   git clone https://github.com/yourusername/project_flutter.git
   cd project_flutter
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

---

## 📱 Permissions

ResQ requires the following permissions to function in an emergency:
- **Location**: To pinpoint SOS coordinates and filter local disasters.
- **Bluetooth**: To scan for and advertise mesh packets.
- **Microphone**: To decode ultrasonic SOS signals (optional).

---

## 🤝 Contribution

This is a hackathon project! Ideas for future improvements:
- WiFi Direct integration for high-bandwidth file sharing.
- LoRa hardware integration for long-range (km+) communication.

---

## ⚖️ License

**© 2026 ResQ Team. All Rights Reserved.**

This project is submitted for **Hackathon Evaluation Only**.
- ✅ **Allowed**: Judges may view, build, and run the code for evaluation.
- ❌ **Prohibited**: Commercial use, redistribution, or modification without permission is strictly forbidden.

See [LICENSE](LICENSE) for full legal text.

