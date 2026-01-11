# AnchorMesh
### 2025 Alameda Hackathon (Jan 1 - 11)

**"Everyone is a Carrier."**

AnchorMesh is a **Store-and-Forward Offline Mesh Network** designed to facilitate communication during natural disasters when cellular networks and Wi-Fi infrastructure fail. It leverages the ubiquity of smartphones to create a decentralized rescue network, turning every device into a potential relay node.

## Overview
In the immediate aftermath of earthquakes, floods, or wildfires, communication is often the first system to collapse. AnchorMesh provides a resilient fallback layer by using Bluetooth Low Energy (BLE) to pass small, encrypted data packets between devices. These packets hop from phone to phone until they reach a device with Internet connectivity, at which point the data is synchronized with emergency services.

## Key Features

### Resilient Mesh Networking
*   **Epidemic Routing**: Utilizes a store-and-forward protocol where every node carries messages for others.
*   **Zero Infrastructure**: Operates entirely offline without cell towers or satellites.
*   **Cross-Platform**: Seamless communication between Android and iOS devices.

### Battery-Conscious Design
*   **Intelligent Cycling**: Devices cycle between scanning and sleeping states to extend battery life up to 24+ hours.
*   **Low Energy**: Optimized BLE usage minimizes power consumption while maintaining network discovery.

### Disaster-Specific Protocol
*   **Small Packet Size**: SOS messages are highly compressed (~25 bytes) to maximize propagation probability.
*   **Coordinate Encoding**: GPS coordinates are encoded as scaled integers for precision without overhead.
*   **Prioritized Traffic**: Differentiates between Critical (Red) and Medical (Yellow) alerts.

## Technical Implementation

### Core Technology
*   **Language**: Dart (Flutter)
*   **Communication**: Bluetooth Low Energy (BLE) 4.0 / 5.0
*   **Mobile Database**: SQLite (for local packet storage)

### iOS Specifics
Due to strict background limitations on iOS, AnchorMesh employs:
*   **Background Overflow Scanning**: Listens for hashed UUIDs in the manufacturer data overflow area.
*   **State Restoration**: Preserves BLE central/peripheral manager states across app termination.

### Android Specifics
*   **Foreground Service**: Ensures continuous operation even when the app is minimized.
*   **Battery Optimization Exemption**: Prevents the OS from killing the mesh service during long-term operation.

## Usage Guide
1.  **Broadcast**: In an emergency, a user initiates an SOS. The app packs location, timestamp, and status into a BLE advertisement.
2.  **Relay**: Nearby devices (Passersby) automatically detect and store the packet without user intervention.
3.  **Transport**: As the passerby moves, they physically carry the message to new areas.
4.  **Sync**: Once a device enters an area with Internet connectivity, all stored SOS messages are uploaded to the cloud.

## License
This project is submitted for the 2025 Alameda Hackathon. It is provided for **evaluation and judging purposes only**.
No part of this codebase may be copied, modified, redistributed, or used for commercial purposes without explicit permission.

See `LICENSE` file for full terms.
