# SOS Emergency Alert System

A cross-platform Flutter application with BLE mesh networking capabilities for emergency SOS alerts. When internet connectivity is unavailable, alerts are relayed through nearby devices via Bluetooth until reaching a device with internet access that can forward the alert to the backend server.

## Features

- **BLE Mesh Networking**: Relay SOS alerts through nearby devices via Bluetooth Low Energy
- **Dual Connectivity**: Send alerts directly via internet when available, or through mesh network when offline
- **Multiple Emergency Types**: Medical, Fire, Security, Natural Disaster, Accident, and Other
- **Real-time Status**: Track how many peers received your alert and server delivery status
- **Message Signing**: Cryptographic signatures to verify message authenticity
- **Auto-relay**: Automatically relay nearby SOS alerts to extend mesh reach
- **Cross-platform**: Works on both iOS and Android

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Device A       │ BLE │  Device B       │ BLE │  Device C       │
│  (No Internet)  │────>│  (No Internet)  │────>│  (Has Internet) │
│                 │     │                 │     │        │        │
│  SOS Initiated  │     │  Relay Alert    │     │   ┌────v────┐   │
└─────────────────┘     └─────────────────┘     │   │  API    │   │
                                                │   │  Call   │   │
                                                │   └────┬────┘   │
                                                └────────┼────────┘
                                                         │
                                                         v
                                                ┌─────────────────┐
                                                │  Backend Server │
                                                │  (Dashboard)    │
                                                └─────────────────┘
```

## Project Structure

```
flutter_Project_Hackathone/
├── lib/
│   ├── models/
│   │   ├── sos_alert.dart       # SOS message model
│   │   ├── device_info.dart     # Device information model
│   │   └── peer_device.dart     # BLE peer device model
│   ├── services/
│   │   ├── ble/
│   │   │   └── ble_mesh_service.dart   # BLE mesh networking
│   │   ├── connectivity/
│   │   │   └── connectivity_service.dart # Network monitoring
│   │   ├── api/
│   │   │   └── api_service.dart         # HTTP/WebSocket client
│   │   ├── crypto/
│   │   │   └── encryption_service.dart  # Message signing
│   │   └── sos/
│   │       └── sos_manager.dart         # Main orchestrator
│   └── pages/
│       └── sos_page.dart        # SOS UI
├── backend/
│   ├── server.js                # Express server entry point
│   ├── config/
│   │   └── db.js               # MongoDB connection
│   ├── middleware/
│   │   ├── auth.js             # JWT authentication
│   │   ├── errorHandler.js     # Error handling
│   │   └── validator.js        # Request validation
│   ├── models/
│   │   ├── Device.js           # Device model
│   │   └── SOSAlert.js         # SOS alert model
│   ├── routes/
│   │   ├── device.routes.js    # Device endpoints
│   │   └── sos.routes.js       # SOS endpoints
│   └── services/
│       ├── websocket.js        # WebSocket for dashboard
│       └── verification.js     # Signature verification
└── README.md
```

## Prerequisites

- Flutter SDK ^3.10.0
- Node.js >= 18.0.0
- MongoDB (local or cloud)
- Physical devices for BLE testing (simulators don't support BLE)

## Backend Setup

1. Navigate to the backend directory:
```bash
cd backend
```

2. Install dependencies:
```bash
npm install
```

3. Create environment file:
```bash
cp .env.example .env
```

4. Edit `.env` with your configuration:
```env
PORT=3000
NODE_ENV=development
MONGODB_URI=mongodb://localhost:27017/sos_mesh_db
JWT_SECRET=your-secret-key-change-this
APP_SIGNATURE_SECRET=your-app-signature-secret
```

5. Start MongoDB (if running locally):
```bash
# Using Docker
docker run -d -p 27017:27017 --name mongodb mongo

# Or start local MongoDB service
mongod --dbpath /path/to/data
```

6. Start the server:
```bash
# Development
npm run dev

# Production
npm start
```

7. Verify the server is running:
```bash
curl http://localhost:3000/health
```

## Flutter App Setup

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. Update the server URL in `lib/pages/sos_page.dart`:
```dart
_sosManager = SOSManager(
  config: const SOSManagerConfig(
    serverBaseUrl: 'http://YOUR_SERVER_IP:3000',
  ),
);
```

3. Run on a physical device:
```bash
flutter run
```

## Platform Configuration

### iOS

Add to `ios/Runner/Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to send and receive emergency SOS alerts.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to broadcast SOS alerts.</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
</array>
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />

<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

## API Endpoints

### Device Registration
```
POST /api/v1/device/register
Body: { deviceId, platform, appVersion, osVersion, deviceModel }
Response: { token, appSignature }
```

### Send SOS Alert
```
POST /api/v1/sos/alert
Headers: Authorization: Bearer <token>
Body: { messageId, originatorDeviceId, emergencyType, priority, location, message, signature, appSignature }
```

### Send Relayed SOS
```
POST /api/v1/sos/relay
Headers: Authorization: Bearer <token>
Body: { ...sosAlert, relayedBy, hopCount, relayChain }
```

### Cancel SOS
```
POST /api/v1/sos/:messageId/cancel
Headers: Authorization: Bearer <token>
```

### Get Active Alerts
```
GET /api/v1/sos/active
Headers: Authorization: Bearer <token>
```

## WebSocket Events

Connect to `ws://localhost:3000/ws`

### Authentication
```json
{ "type": "auth", "token": "<jwt_token>" }
```

### Events Received
- `new_sos_alert`: New SOS alert received
- `sos_update`: Alert status changed
- `sos_acknowledged`: Alert acknowledged by server

## Testing

### Backend
```bash
cd backend
npm test
```

### Flutter
```bash
flutter test
```

### Integration Testing
1. Start the backend server
2. Run the app on two physical devices
3. Enable airplane mode on one device
4. Initiate SOS on the offline device
5. Verify the alert is relayed through the online device to the server

## Security Considerations

- All messages are signed with HMAC-SHA256
- JWT tokens for device authentication
- App signature verification prevents unauthorized clients
- HTTPS recommended for production
- Rate limiting on API endpoints

## Troubleshooting

### BLE not discovering devices
- Ensure Bluetooth is enabled on both devices
- Grant location permissions (required for BLE scanning on Android)
- Physical devices required (simulators don't support BLE)

### Server connection failed
- Verify server is running (`curl http://localhost:3000/health`)
- Check firewall settings
- Ensure correct IP address in Flutter app config

### MongoDB connection issues
- Verify MongoDB is running
- Check connection string in `.env`
- Ensure network access if using cloud MongoDB

## License

MIT License
