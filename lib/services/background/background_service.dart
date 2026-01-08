import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../storage/database_service.dart';

// Task identifiers
const String checkConnectivityTask = "com.example.project_flutter.check_connectivity";
const String uploadDataTask = "com.example.project_flutter.upload_data";

// Entry point for background tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case checkConnectivityTask:
        return await _handleConnectivityCheck();
      case uploadDataTask:
        return await _handleDataUpload();
      default:
        return Future.value(true);
    }
  });
}

Future<bool> _handleConnectivityCheck() async {
  final connectivityResult = await Connectivity().checkConnectivity();
  if (connectivityResult == ConnectivityResult.none) {
    // No internet, do nothing or trigger BLE scan if needed
    // In "Smart Trigger" logic: if no internet, we might want to activate Mesh if not already
    return Future.value(true);
  }

  // Has potential internet, verify with Ping
  try {
    final response = await http.get(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      // Internet confirmed! Trigger upload.
      await _handleDataUpload();
    }
  } catch (e) {
    // Ping failed, assume no internet
  }
  
  return Future.value(true);
}

Future<bool> _handleDataUpload() async {
  final db = DatabaseService();
  final pendingMessages = await db.getPendingMessages();

  if (pendingMessages.isEmpty) {
    await db.close();
    return Future.value(true);
  }

  final uploadedIds = <String>[];
  
  for (final msg in pendingMessages) {
    try {
      // Fake upload for now
      // final response = await http.post(...)
      
      // Simulate success
      uploadedIds.add(msg['message_id'] as String);
    } catch (e) {
      // Failed, keep for next time
    }
  }

  if (uploadedIds.isNotEmpty) {
    await db.markAsSynced(uploadedIds);
  }

  await db.close();
  return Future.value(true);
}

class BackgroundService {
  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  Future<void> registerPeriodicCheck() async {
    // Minimum 15 minutes on Android
    await Workmanager().registerPeriodicTask(
      "1", 
      checkConnectivityTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}
