# SOS Mesh Implementation Details

This project now implements the "Active SOS" Mesh Networking system with the following key features:

## 1. Strict Binary Protocol (21 Bytes)
We have implemented the 21-byte `SOSBeacon` to fit within the Legacy BLE Advertising payload (31 bytes).
- **Header:** 0xFFFF (2 bytes)
- **User ID:** 4 bytes
- **Sequence:** 2 bytes
- **Location:** Lat/Lon (4 bytes each, int-encoded)
- **Status:** 1 byte
- **Timestamp:** 4 bytes

## 2. Store-and-Forward (SQLite)
- **Database:** `lib/services/storage/database_service.dart`
- **Logic:**
  - Incoming packets are saved with `status: pending`.
  - Duplicates are ignored based on `MessageID` (UserID + Sequence).
  - "Smart Trigger" (Workmanager) wakes up every 15 mins to check for internet.
  - If internet is found -> Uploads pending messages -> Marks as synced.

## 3. Background Execution
- **Android:** Uses `Workmanager` for periodic checks and `ForegroundService` (via `flutter_background_service` or native equivalent if configured) for active scanning.
- **iOS:**
  - Configured `Info.plist` for `bluetooth-central`, `bluetooth-peripheral`, `fetch`, and `processing`.
  - Registered `WorkmanagerPlugin` in `AppDelegate.swift`.
  - Uses `restoreState: true` (implied by background mode) for persistent BLE.

## 4. BLE Mesh Service
- **Service:** `lib/services/ble/ble_mesh_service.dart`
- **Scanning:** Continuous updates (replaced `allowDuplicates` with `continuousUpdates`).
- **Advertising:** Uses `BLEPeripheralService` (Native Channel) to broadcast the strict beacon.

## How to Test
1. **Run on Physical Device:** BLE does not work on simulators.
2. **Permissions:** Grant Location (Always Allow) and Bluetooth permissions.
3. **Trigger SOS:** Call `bleMeshService.broadcastSOS(alert)`.
4. **Observe:**
   - Other devices should see `PeerDiscoveredEvent` and `MessageReceivedEvent`.
   - Data is saved to `sos_mesh.db` (SQLite).
   - Log output will show "Handling received beacon...".

## Next Steps
- **UI Integration:** Connect `BLEMeshService.events` to your `MapPage` and `SOSPage`.
- **Server API:** Implement the actual HTTP POST in `BackgroundService._handleDataUpload`.
- **Low Power Mode:** Add a UI listener for `NSProcessInfo.processInfo.isLowPowerModeEnabled` to warn users.
