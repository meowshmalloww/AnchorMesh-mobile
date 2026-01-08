import 'package:flutter_test/flutter_test.dart';
import 'package:project_flutter/services/ble/ble_peripheral_service.dart';

void main() {
  group('SOSBeacon Tests', () {
    test('Should serialize to strict 21 bytes', () {
      final beacon = SOSBeacon(
        userId: 0x12345678,
        sequence: 0xABCD,
        latitude: 40.7128, // NYC
        longitude: -74.0060,
        status: 1,
        timestamp: 1704067200, // 2024-01-01
      );

      final bytes = beacon.toBytes();
      
      expect(bytes.length, 21);
      
      // Header 0xFFFF
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xFF);
      
      // UserID 0x12345678
      expect(bytes[2], 0x12);
      expect(bytes[3], 0x34);
      expect(bytes[4], 0x56);
      expect(bytes[5], 0x78);
      
      // Sequence 0xABCD
      expect(bytes[6], 0xAB);
      expect(bytes[7], 0xCD);
      
      // Status
      expect(bytes[16], 1);
    });

    test('Should deserialize correctly (Round Trip)', () {
      final originalBeacon = SOSBeacon(
        userId: 0x12345678,
        sequence: 1,
        latitude: 40.7128,
        longitude: -74.0060,
        status: 1,
        timestamp: 1704067200,
      );

      final bytes = originalBeacon.toBytes();
      final decodedBeacon = SOSBeacon.fromBytes(bytes);
      
      expect(decodedBeacon, isNotNull);
      expect(decodedBeacon!.userId, originalBeacon.userId);
      expect(decodedBeacon.sequence, originalBeacon.sequence);
      // Allow small epsilon for float precision loss during int encoding
      expect(decodedBeacon.latitude, closeTo(originalBeacon.latitude, 0.00001));
      expect(decodedBeacon.longitude, closeTo(originalBeacon.longitude, 0.00001));
      expect(decodedBeacon.status, originalBeacon.status);
    });

    test('Should reject invalid header', () {
      final inputBytes = List<int>.filled(21, 0);
      inputBytes[0] = 0xAA; // Wrong header
      
      final beacon = SOSBeacon.fromBytes(inputBytes);
      expect(beacon, isNull);
    });
  });
}
