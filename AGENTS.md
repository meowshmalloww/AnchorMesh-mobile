# AGENTS.md - AI Agent Guidelines

This document provides context and guidelines for AI agents working on this SOS Emergency Alert System codebase.

## Project Overview

This is a **Flutter mobile application** with a **Node.js backend** that enables emergency SOS alerts through BLE (Bluetooth Low Energy) mesh networking. The key innovation is that when a device lacks internet connectivity, SOS alerts are relayed through nearby devices via Bluetooth until reaching a device with internet access.

## Architecture Summary

### Flutter App (`lib/`)

| Component | Location | Purpose |
|-----------|----------|---------|
| **Models** | `lib/models/` | Data structures for SOS alerts, devices, and peers |
| **BLE Service** | `lib/services/ble/` | Bluetooth mesh networking, scanning, advertising |
| **Connectivity** | `lib/services/connectivity/` | Network state monitoring |
| **API Service** | `lib/services/api/` | HTTP/WebSocket communication with backend |
| **Crypto** | `lib/services/crypto/` | Message signing and verification |
| **SOS Manager** | `lib/services/sos/` | Main orchestrator coordinating all services |
| **Pages** | `lib/pages/` | UI components |

### Backend (`backend/`)

| Component | Location | Purpose |
|-----------|----------|---------|
| **Server** | `server.js` | Express entry point with WebSocket |
| **Models** | `models/` | Mongoose schemas (Device, SOSAlert) |
| **Routes** | `routes/` | API route definitions |
| **Controllers** | `controllers/` | Business logic |
| **Middleware** | `middleware/` | Auth, validation, error handling |
| **Services** | `services/` | WebSocket, signature verification |

## Key Concepts

### BLE Mesh Relay

1. Device A initiates SOS (no internet)
2. Alert is broadcast via BLE to nearby devices
3. Device B receives and relays (also no internet)
4. Device C receives, has internet, sends to server
5. Server notifies dashboards via WebSocket

### Message Flow

```
SOSManager.initiateSOS()
    │
    ├─► ConnectivityService.hasInternet?
    │   ├─► YES: ApiService.sendSosAlert() + BLEMeshService.broadcastSOS()
    │   └─► NO: BLEMeshService.broadcastSOS() only
    │
    └─► On connectivity change:
        └─► If internet available: Send pending alerts to server
```

### Message Signing

All SOS messages are signed with HMAC-SHA256 to ensure:
1. Message originated from the legitimate app
2. Message wasn't tampered with during relay

## Important Files to Understand

### Core Flutter Files

1. **`lib/services/sos/sos_manager.dart`** - The main orchestrator. Start here to understand how everything connects.

2. **`lib/services/ble/ble_mesh_service.dart`** - BLE scanning, advertising, and peer communication.

3. **`lib/models/sos_alert.dart`** - The SOS message structure including emergency types, priority, location, and relay tracking.

### Core Backend Files

1. **`backend/controllers/sos.controller.js`** - Handles incoming SOS alerts (direct and relayed).

2. **`backend/services/websocket.js`** - Real-time communication with dashboards.

3. **`backend/services/verification.js`** - Message signature verification.

## Common Tasks

### Adding a New Emergency Type

1. Add to `EmergencyType` enum in `lib/models/sos_alert.dart`
2. Add display name in the `displayName` getter
3. Update `_getEmergencyIcon()` in `lib/pages/sos_page.dart`
4. Add to validation in `backend/middleware/validator.js`

### Adding a New API Endpoint

1. Create route in `backend/routes/`
2. Create controller function in `backend/controllers/`
3. Add validation rules in `backend/middleware/validator.js`
4. Update `ApiService` in `lib/services/api/api_service.dart`

### Modifying BLE Behavior

- Scan settings: `BleMeshConfig` in `lib/services/ble/ble_mesh_service.dart`
- Service UUIDs: `BleUuids` class
- Peer handling: `_processScanResult()` and `_processReceivedSosData()`

## Testing Considerations

- **BLE requires physical devices** - Simulators don't support Bluetooth
- **Test with multiple devices** to verify mesh relay
- **Test offline scenarios** - Enable airplane mode on test devices
- **Backend can be tested independently** with curl/Postman

## Environment Variables

### Backend (`.env`)
```
PORT=3000
MONGODB_URI=mongodb://localhost:27017/sos_mesh_db
JWT_SECRET=<secret>
APP_SIGNATURE_SECRET=<secret>
```

### Flutter
Update `serverBaseUrl` in `SOSManagerConfig` for your environment.

## Dependencies

### Flutter Key Dependencies
- `flutter_blue_plus` - BLE communication
- `connectivity_plus` - Network state
- `geolocator` - Location services
- `flutter_secure_storage` - Secure credential storage
- `crypto` - Cryptographic operations

### Backend Key Dependencies
- `express` - Web framework
- `mongoose` - MongoDB ODM
- `jsonwebtoken` - JWT authentication
- `ws` - WebSocket support
- `winston` - Logging

## Code Style Notes

- Flutter uses `ChangeNotifier` for state management (Provider pattern)
- Backend uses async/await with Express `asyncHandler` wrapper
- All database operations use Mongoose models
- Error handling centralized in `errorHandler` middleware

## Security Considerations

When making changes:
1. Never log sensitive data (tokens, signatures)
2. Validate all input on both client and server
3. Use parameterized queries (Mongoose handles this)
4. Keep JWT secrets secure
5. Rate limit sensitive endpoints

## Debugging Tips

1. **BLE issues**: Check `BLEMeshService.events` stream for errors
2. **API issues**: Check server logs and `ApiService` responses
3. **State issues**: Use Flutter DevTools to inspect Provider state
4. **WebSocket issues**: Check `ServerEvent` stream in `ApiService`
