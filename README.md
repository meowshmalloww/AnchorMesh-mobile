# AnchorMesh ⚓
### 2025 Alameda Hackathon (Jan 1 - 11)

**"Even if you don’t need rescue, hold out the phone so SOS messages can pass through!"**

AnchorMesh is a **Store-and-Forward Offline Mesh Network** designed for natural disasters when cell service and Wi-Fi fail. It turns every smartphone into a rescue node, creating a decentralized network where "Everyone is a Carrier."

---

## 📱 Key Highlights
*   **App Size**: Optimized (< 100MB)
*   **Battery First**: Intelligent Sleep/Scan windows to run 24+ hours.
*   **Secure Public**: "Epidemic Routing" - Packets are encrypted and public; devices relay them without knowing the content.
*   **Tech Stack**: Flutter + Dart (Cross-Platform).

## 🌪️ Built For Natural Disasters
Designed to work during:
*   Earthquakes, Tsunamis, Volcanic Eruptions
*   Floods, Hurricanes, Tornadoes, Wildfires

### 🚨 Alert Levels
*   🔴 **Red (Critical)**: Trapped, immediate danger.
*   🟡 **Yellow (Injured)**: Need medical aid or supplies.
*   🟢 **Green (Safe)**: "I AM SAFE" - Stops the SOS propagation for this user.

> **Note**: Users cannot edit the SOS message text manually. They can only select from pre-defined, compressed status codes to ensure data integrity and small packet size.

---

## 📡 The Mesh: Epidemic Routing
AnchorMesh uses **Store-and-Forward** logic:

1.  **User A (Trapped)**: Posts an SOS.
2.  **User B (Passerby)**: Comes within range. Their phone silently downloads User A's packet.
3.  **User B Walks**: They carry the packet until they meet User C or find Internet.
4.  **Internet Sync**: If User B finds a signal, the app automatically uploads User A's message to the Rescue Server.

### 📶 Bluetooth Low Energy (BLE) Specs
*   **Range**: 30-100m (Indoor/Urban), up to 400m (Open Air).
*   **MTU (Maximum Transmission Unit)**:
    *   **Android**: Up to 514 bytes (configurable).
    *   **iOS**: System managed (typically 185-527 bytes depending on model).
*   **Connections**: Phones maintain 3-7 simultaneous connections.

### 💾 Data Compression & Protocol
To maximize reliability, we compress GPS coordinates into **Integers**:

*   **Float64 (Standard)**: 16 bytes (Too large)
*   **AnchorMesh Optimization**:
    *   Formula: `round(Coordinate * 10^7)`
    *   Example: `40.6424741` → `406424741` (Fits in 4 bytes)
    *   **Precision**: ~1.1 cm (Rescue grade)
    *   **Total Packet Size**: ~25 Bytes.

**Packet Blueprint:**
| Byte | Field | Size | Details |
|------|-------|------|---------|
| 0-1 | **Header** | 2B | `0xFFFF` (App Handshake) |
| 2-5 | **User ID** | 4B | Random 32-bit Integer |
| 6-7 | **Sequence** | 2B | Counter (increments on move) |
| 8-11 | **Latitude** | 4B | Scaled Integer (`Lat * 10^7`) |
| 12-15 | **Longitude**| 4B | Scaled Integer (`Lon * 10^7`) |
| 16 | **Status** | 1B | `0x00`=Safe, `0x01`=SOS, etc. |
| 17-20| **Timestamp**| 4B | Unix Seconds (Epoch) |

---

## 🤖 Platform Specifics

### iOS Implementation 🍎
*   **Foreground**: Sets `isIdleTimerDisabled = true` to keep screen/radio active.
*   **Background**:
    *   **Scanning**: BLE Background Mode listens for our Service UUID (`1234...`).
    *   **Broadcasting**: Moves data to the "Overflow Area" (Hashed UUID).
    *   **Wake Up**: If a signal is detected, iOS wakes the app for ~10 seconds to process/relay.
*   **Limitations**:
    *   **Low Power Mode**: Cannot be overridden. App warnings user to disable it.
    *   **Throttling**: Background scans are strictly managed by iOS.

### Android Implementation 🤖
*   **Battery Optimization**: App requests `ACTION_IGNORE_BATTERY_OPTIMIZATIONS` for continuous background scanning.
*   **Boot Receiver**: Auto-starts the "Rescue Listener" service on phone reboot (silent operation).
*   **Dual-Mode Advertising**:
    *   **Legacy (4.x)**: Small packets (31 bytes), compatible with all phones.
    *   **Extended (5.0+)**: larger packets (255+ bytes), better range/speed.

---

## ⚡ Smart Triggers & Automation
The Mesh doesn't run 24/7 to save battery. It auto-activates based on:

1.  **Internet Loss**: Pings Google/Apple. If 3 consecutive failures occur over 1 hour -> **Auto-Activate SOS Mode**.
2.  **API Alerts**: Background fetch (every 30 mins) checks USGS/NOAA.
    *   **Magnitude 6.0+ Earthquake** OR **Severe Weather** in Zip Code -> **Wake Up & Scan**.
3.  **Boot Recovery**: Android automatically restarts the listener after a device reboot.

## 🔋 Battery Strategy
| Mode | Scan Window | Sleep Window | Est. Battery Life |
|------|-------------|--------------|-------------------|
| **SOS Active** | Always On | None | 6-8 Hours |
| **Bridge (Default)** | 30 Seconds | 30 Seconds | 12+ Hours |
| **Battery Saver** | 5 Seconds | 55 Seconds | 24+ Hours |
| **Level 5 (Peace)** | OFF | OFF | Normal Phone Usage |

---

## 🛠️ Offline Utilities
Since the internet is gone, AnchorMesh provides survival tools:
*   **Ultrasonic SOS** 🔊: Encodes SOS data into high-freq audio (17kHz-20kHz) for verified close-range (1-5m) transfer.
*   **Signal Locator** ♨️: "Hot/Cold" RSSI meter to find victims behind rubble.
*   **Map**: Offline tile support (OpenStreetMap).
*   **Compass**: Magnetic heading.

---

## 🔄 Sync & Feedback
*   **Echo Feedback**: If you hear your *own* packet broadcast by someone else, the app notifies you: "Signal Relayed! 2 copies nearby."
*   **Cloud Sync**: When Internet returns, the app uploads all stored packets to the server.
    *   **Kill Switch**: Receiving a server acknowledgement deletes the local packet to stop the mesh from echoing old data.
*   **Deduplication**: Remembers `UUID + Sequence`. Ignores duplicates, processes only new info (Sequence N+1).

---

> **Note**: This project acts as a "Two-Way" system. Rescuers can broadcast "Targeted Messages" (e.g., Supply Drop Location) back into the mesh to reach specific victims.
