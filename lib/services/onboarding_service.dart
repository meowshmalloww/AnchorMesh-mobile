import 'package:shared_preferences/shared_preferences.dart';

/// Service to track onboarding completion state
class OnboardingService {
  static const String _onboardingCompleteKey = 'onboarding_complete';
  static const String _onboardingVersionKey = 'onboarding_version';
  
  /// Current onboarding version - increment this to force re-onboarding
  /// when significant new permissions or features are added
  static const int currentVersion = 1;

  static OnboardingService? _instance;
  SharedPreferences? _prefs;

  OnboardingService._();

  static OnboardingService get instance {
    _instance ??= OnboardingService._();
    return _instance!;
  }

  Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if onboarding has been completed for the current version
  Future<bool> isOnboardingComplete() async {
    await _ensureInitialized();
    final isComplete = _prefs!.getBool(_onboardingCompleteKey) ?? false;
    final version = _prefs!.getInt(_onboardingVersionKey) ?? 0;
    
    // If version changed, require re-onboarding
    if (version < currentVersion) {
      return false;
    }
    
    return isComplete;
  }

  /// Mark onboarding as complete for the current version
  Future<void> completeOnboarding() async {
    await _ensureInitialized();
    await _prefs!.setBool(_onboardingCompleteKey, true);
    await _prefs!.setInt(_onboardingVersionKey, currentVersion);
  }

  /// Reset onboarding state (for testing or settings)
  Future<void> resetOnboarding() async {
    await _ensureInitialized();
    await _prefs!.setBool(_onboardingCompleteKey, false);
  }
}
