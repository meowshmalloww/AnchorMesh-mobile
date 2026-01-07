import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class SOSPage extends StatefulWidget {
  const SOSPage({super.key});

  @override
  State<SOSPage> createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage> {
  String _locationMessage = "Fetching location...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Manual only - Efficiency
    _locationMessage = "Tap below to get current location";
    _isLoading = false;
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _locationMessage = "Location services are disabled.";
          _isLoading = false;
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _locationMessage = "Location permissions are denied";
            _isLoading = false;
          });
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _locationMessage =
              "Location permissions are permanently denied, we cannot request permissions.";
          _isLoading = false;
        });
      }
      return;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _locationMessage =
              "Lat: ${position.latitude.toStringAsFixed(4)}, Long: ${position.longitude.toStringAsFixed(4)}";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationMessage = "Error getting location: $e";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine colors based on theme, as SOS page might want to stand out
    // or follow the theme. The requirement was "SOS button".
    // We'll keep the background neutral/theme-based and the button RED.

    return Scaffold(
      appBar: AppBar(
        title: const Text("SOS"),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // SOS Button
            Material(
              color: Colors.red,
              shape: const CircleBorder(),
              elevation: 10,
              child: InkWell(
                onTap: () {
                  // "Clickable but does nothing"
                  debugPrint("SOS Button Pressed");
                },
                customBorder: const CircleBorder(),
                child: Container(
                  width: 200,
                  height: 200,
                  alignment: Alignment.center,
                  child: const Text(
                    "SOS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            // GPS Location
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                "Current Location:",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 10),
            _isLoading
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      _locationMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _getCurrentLocation,
              icon: const Icon(Icons.refresh),
              label: const Text("Refresh Location"),
            ),
          ],
        ),
      ),
    );
  }
}
