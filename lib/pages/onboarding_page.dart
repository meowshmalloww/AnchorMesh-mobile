import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/resq_theme.dart';
import '../services/onboarding_service.dart';
import '../home_screen.dart';

/// Simple onboarding screen that requests permissions progressively
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  // Total pages: Welcome, Location, Notifications
  // Bluetooth permission is triggered automatically when BLE is used
  static const int _totalPages = 3;

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  Future<void> _requestLocationPermission() async {
    setState(() => _isLoading = true);

    try {
      // Request location permission
      var status = await Permission.locationWhenInUse.request();
      debugPrint('Location when in use status: $status');

      if (status.isGranted) {
        // Try to get "always" permission too
        if (Platform.isIOS) {
          final alwaysStatus = await Permission.locationAlways.request();
          debugPrint('Location always status: $alwaysStatus');
        }
        _nextPage();
      } else if (status.isPermanentlyDenied) {
        _showSettingsDialog(
          'Location Required',
          'Location permission is needed to share your GPS coordinates in SOS signals. Please enable it in Settings.',
        );
      } else {
        // User denied but can try again
        _showRetryDialog(
          'Location Required',
          'Location is needed so rescuers can find you during emergencies.',
          _requestLocationPermission,
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _isLoading = true);

    try {
      final status = await Permission.notification.request();
      debugPrint('Notification status: $status');

      // Always proceed - notifications are optional
      _completeOnboarding();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSettingsDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _nextPage(); // Proceed anyway
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showRetryDialog(String title, String message, VoidCallback onRetry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _nextPage(); // Proceed anyway
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    await OnboardingService.instance.completeOnboarding();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage >= index
                          ? colors.accent
                          : colors.meshNode,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomePage(colors),
                  _buildLocationPage(colors),
                  _buildNotificationPage(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ResQColors colors) {
    return _buildPage(
      colors: colors,
      icon: Icons.emergency,
      iconColor: colors.accent,
      title: 'Welcome to AnchorMesh',
      description:
          'Your lifeline when networks fail.\n\n'
          'AnchorMesh uses Bluetooth to create a mesh network with nearby devices, '
          'allowing you to send and receive SOS signals even without internet.',
      buttonText: 'Get Started',
      onPressed: _nextPage,
    );
  }

  Widget _buildLocationPage(ResQColors colors) {
    return _buildPage(
      colors: colors,
      icon: Icons.location_on,
      iconColor: Colors.blue,
      title: 'Enable Location',
      description:
          'Your GPS coordinates are included in SOS signals so rescuers can find you.\n\n'
          'We only access your location when you send an emergency alert.',
      buttonText: 'Enable Location',
      onPressed: _requestLocationPermission,
    );
  }

  Widget _buildNotificationPage(ResQColors colors) {
    return _buildPage(
      colors: colors,
      icon: Icons.notifications_active,
      iconColor: colors.accent,
      title: 'Stay Alerted',
      description:
          'Receive notifications when SOS signals are detected nearby.\n\n'
          'These alerts could help you save a life or help others find you in an emergency.',
      buttonText: 'Enable Notifications',
      onPressed: _requestNotificationPermission,
    );
  }

  Widget _buildPage({
    required ResQColors colors,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),

          // Icon
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 70, color: iconColor),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: colors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const Spacer(),

          // Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
