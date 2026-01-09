import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'version_detector.dart';

/// Native theme integration service for iOS 26 Liquid Glass and Android Material You.
///
/// This service provides a unified interface for applying platform-native
/// design elements across iOS and Android:
/// - iOS 26+: Liquid Glass translucent material with dynamic reflections
/// - Android: Material You dynamic color theming
///
/// Usage:
/// ```dart
/// final service = LiquidGlassService.instance;
/// await service.initialize();
///
/// // Apply Liquid Glass to a specific element
/// await service.applyLiquidGlass('navbar', intensity: 0.8);
///
/// // Get system accent color for theming
/// final color = await service.getSystemAccentColor();
/// ```
class LiquidGlassService {
  static const _channel = MethodChannel('com.project_flutter/liquid_glass');
  static const _eventChannel = EventChannel('com.project_flutter/liquid_glass_events');

  static LiquidGlassService? _instance;

  static LiquidGlassService get instance {
    _instance ??= LiquidGlassService._();
    return _instance!;
  }

  LiquidGlassService._();

  // State
  bool _isInitialized = false;
  bool _isLiquidGlassSupported = false;
  bool _isMaterialYouSupported = false;
  int? _systemAccentColor;
  LiquidGlassConfig _currentConfig = LiquidGlassConfig.defaultConfig;

  // Streams
  final _themeChangeController = StreamController<NativeThemeEvent>.broadcast();
  StreamSubscription? _eventSubscription;

  /// Stream of native theme change events
  Stream<NativeThemeEvent> get onThemeChange => _themeChangeController.stream;

  /// Whether iOS Liquid Glass is supported (iOS 26+)
  bool get isLiquidGlassSupported => _isLiquidGlassSupported;

  /// Whether Android Material You is supported (Android 12+)
  bool get isMaterialYouSupported => _isMaterialYouSupported;

  /// Current system accent color (ARGB int)
  int? get systemAccentColor => _systemAccentColor;

  /// Current Liquid Glass configuration
  LiquidGlassConfig get currentConfig => _currentConfig;

  /// Initialize the service and detect platform capabilities
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize version detector first
      await VersionDetector.instance.initialize();

      // Listen for native theme events
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        _handleNativeEvent,
        onError: (dynamic error) {
          debugPrint('LiquidGlassService: Event error: $error');
        },
      );

      // Check platform capabilities via method channel
      final capabilities = await _channel.invokeMethod<Map>('getCapabilities');
      if (capabilities != null) {
        _isLiquidGlassSupported = capabilities['liquidGlassSupported'] as bool? ?? false;
        _isMaterialYouSupported = capabilities['materialYouSupported'] as bool? ?? false;
        _systemAccentColor = capabilities['systemAccentColor'] as int?;
      }

      // Cross-validate with version detector for accuracy
      if (Platform.isIOS) {
        final supportsLG = await VersionDetector.instance.supportsLiquidGlass();
        // Only enable if both native and version detector agree
        _isLiquidGlassSupported = _isLiquidGlassSupported && supportsLG;
      } else if (Platform.isAndroid) {
        final supportsMY = await VersionDetector.instance.supportsMaterialYou();
        _isMaterialYouSupported = _isMaterialYouSupported || supportsMY;
      }

      _isInitialized = true;
      debugPrint('LiquidGlassService initialized: '
          'LiquidGlass=$_isLiquidGlassSupported, '
          'MaterialYou=$_isMaterialYouSupported, '
          'iOS=${VersionDetector.instance.iosMajorVersion}, '
          'AndroidSDK=${VersionDetector.instance.androidSdkVersion}');
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to initialize: ${e.message}');
      _isInitialized = true; // Mark as initialized even on failure
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map) return;

    final type = event['type'] as String?;
    final data = event['data'];

    switch (type) {
      case 'themeChanged':
        _systemAccentColor = data['accentColor'] as int?;
        _themeChangeController.add(NativeThemeEvent(
          type: NativeThemeEventType.themeChanged,
          accentColor: _systemAccentColor,
        ));
        break;
      case 'liquidGlassStateChanged':
        final enabled = data['enabled'] as bool? ?? false;
        _themeChangeController.add(NativeThemeEvent(
          type: NativeThemeEventType.liquidGlassStateChanged,
          liquidGlassEnabled: enabled,
        ));
        break;
    }
  }

  // ==================
  // iOS Liquid Glass
  // ==================

  /// Apply Liquid Glass effect to a native UI element.
  ///
  /// [elementId] identifies the native element to apply the effect to.
  /// Supported element IDs:
  /// - 'navbar': Navigation bar
  /// - 'tabbar': Tab bar
  /// - 'toolbar': Toolbar
  /// - 'sidebar': Sidebar
  /// - 'sheet': Bottom sheet / modal
  /// - 'card': Card views
  /// - 'background': Full background
  ///
  /// [intensity] controls the glass effect strength (0.0 - 1.0).
  /// [tintColor] optional tint color (ARGB int).
  /// [blurRadius] blur amount for the glass effect.
  Future<bool> applyLiquidGlass(
    String elementId, {
    double intensity = 0.8,
    int? tintColor,
    double blurRadius = 20.0,
  }) async {
    if (!Platform.isIOS) {
      debugPrint('LiquidGlassService: Liquid Glass only available on iOS');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('applyLiquidGlass', {
        'elementId': elementId,
        'intensity': intensity,
        'tintColor': tintColor,
        'blurRadius': blurRadius,
      });

      if (result == true) {
        _currentConfig = _currentConfig.copyWith(
          elements: {..._currentConfig.elements, elementId: intensity},
        );
      }

      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to apply Liquid Glass: ${e.message}');
      return false;
    }
  }

  /// Remove Liquid Glass effect from an element
  Future<bool> removeLiquidGlass(String elementId) async {
    if (!Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('removeLiquidGlass', {
        'elementId': elementId,
      });

      if (result == true) {
        final newElements = Map<String, double>.from(_currentConfig.elements);
        newElements.remove(elementId);
        _currentConfig = _currentConfig.copyWith(elements: newElements);
      }

      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to remove Liquid Glass: ${e.message}');
      return false;
    }
  }

  /// Apply global Liquid Glass configuration
  Future<bool> applyGlobalConfig(LiquidGlassConfig config) async {
    if (!Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('applyGlobalLiquidGlassConfig', {
        'enabled': config.enabled,
        'defaultIntensity': config.defaultIntensity,
        'adaptToEnvironment': config.adaptToEnvironment,
        'reduceMotion': config.reduceMotion,
        'elements': config.elements,
      });

      if (result == true) {
        _currentConfig = config;
      }

      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to apply global config: ${e.message}');
      return false;
    }
  }

  /// Check if user has reduced transparency enabled (for accessibility)
  Future<bool> isReducedTransparencyEnabled() async {
    if (!Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isReducedTransparencyEnabled');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ==================
  // Android Material You
  // ==================

  /// Apply Material You dynamic color theme
  ///
  /// [seedColor] optional seed color to generate palette from.
  /// If null, uses system wallpaper colors.
  Future<bool> applyMaterialYou({int? seedColor}) async {
    if (!Platform.isAndroid) {
      debugPrint('LiquidGlassService: Material You only available on Android');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('applyMaterialYou', {
        'seedColor': seedColor,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to apply Material You: ${e.message}');
      return false;
    }
  }

  /// Get the current system accent color
  Future<int?> getSystemAccentColor() async {
    try {
      final result = await _channel.invokeMethod<int>('getSystemAccentColor');
      _systemAccentColor = result;
      return result;
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to get accent color: ${e.message}');
      return null;
    }
  }

  /// Get Material You color palette from system
  Future<MaterialYouPalette?> getMaterialYouPalette() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('getMaterialYouPalette');
      if (result == null) return null;

      return MaterialYouPalette(
        primary: result['primary'] as int?,
        onPrimary: result['onPrimary'] as int?,
        primaryContainer: result['primaryContainer'] as int?,
        onPrimaryContainer: result['onPrimaryContainer'] as int?,
        secondary: result['secondary'] as int?,
        onSecondary: result['onSecondary'] as int?,
        secondaryContainer: result['secondaryContainer'] as int?,
        onSecondaryContainer: result['onSecondaryContainer'] as int?,
        tertiary: result['tertiary'] as int?,
        onTertiary: result['onTertiary'] as int?,
        tertiaryContainer: result['tertiaryContainer'] as int?,
        onTertiaryContainer: result['onTertiaryContainer'] as int?,
        surface: result['surface'] as int?,
        onSurface: result['onSurface'] as int?,
        background: result['background'] as int?,
        onBackground: result['onBackground'] as int?,
      );
    } on PlatformException catch (e) {
      debugPrint('LiquidGlassService: Failed to get palette: ${e.message}');
      return null;
    }
  }

  // ==================
  // Cross-Platform
  // ==================

  /// Apply platform-appropriate native theme
  ///
  /// On iOS: Applies Liquid Glass with specified intensity
  /// On Android: Applies Material You with system colors
  Future<bool> applyNativeTheme({
    double liquidGlassIntensity = 0.8,
    int? materialYouSeedColor,
  }) async {
    if (Platform.isIOS) {
      return await applyLiquidGlass('background', intensity: liquidGlassIntensity);
    } else if (Platform.isAndroid) {
      return await applyMaterialYou(seedColor: materialYouSeedColor);
    }
    return false;
  }

  /// Get platform-appropriate blur effect settings
  NativeBlurSettings getBlurSettings({
    double intensity = 0.8,
    bool adaptToAccessibility = true,
  }) {
    if (Platform.isIOS && _isLiquidGlassSupported) {
      return NativeBlurSettings(
        blurRadius: 20.0 * intensity,
        saturation: 1.8,
        opacity: 0.7 * intensity,
        useLiquidGlass: true,
      );
    } else if (Platform.isAndroid) {
      return NativeBlurSettings(
        blurRadius: 15.0 * intensity,
        saturation: 1.0,
        opacity: 0.9 * intensity,
        useLiquidGlass: false,
      );
    }
    return NativeBlurSettings.defaultSettings;
  }

  /// Dispose resources
  void dispose() {
    _eventSubscription?.cancel();
    _themeChangeController.close();
  }
}

/// Configuration for Liquid Glass effects
class LiquidGlassConfig {
  /// Whether Liquid Glass effects are enabled
  final bool enabled;

  /// Default intensity for new elements (0.0 - 1.0)
  final double defaultIntensity;

  /// Whether to adapt to environmental lighting
  final bool adaptToEnvironment;

  /// Whether to reduce motion for accessibility
  final bool reduceMotion;

  /// Element-specific intensity overrides
  final Map<String, double> elements;

  const LiquidGlassConfig({
    this.enabled = true,
    this.defaultIntensity = 0.8,
    this.adaptToEnvironment = true,
    this.reduceMotion = false,
    this.elements = const {},
  });

  static const defaultConfig = LiquidGlassConfig();

  LiquidGlassConfig copyWith({
    bool? enabled,
    double? defaultIntensity,
    bool? adaptToEnvironment,
    bool? reduceMotion,
    Map<String, double>? elements,
  }) {
    return LiquidGlassConfig(
      enabled: enabled ?? this.enabled,
      defaultIntensity: defaultIntensity ?? this.defaultIntensity,
      adaptToEnvironment: adaptToEnvironment ?? this.adaptToEnvironment,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      elements: elements ?? this.elements,
    );
  }
}

/// Material You color palette
class MaterialYouPalette {
  final int? primary;
  final int? onPrimary;
  final int? primaryContainer;
  final int? onPrimaryContainer;
  final int? secondary;
  final int? onSecondary;
  final int? secondaryContainer;
  final int? onSecondaryContainer;
  final int? tertiary;
  final int? onTertiary;
  final int? tertiaryContainer;
  final int? onTertiaryContainer;
  final int? surface;
  final int? onSurface;
  final int? background;
  final int? onBackground;

  MaterialYouPalette({
    this.primary,
    this.onPrimary,
    this.primaryContainer,
    this.onPrimaryContainer,
    this.secondary,
    this.onSecondary,
    this.secondaryContainer,
    this.onSecondaryContainer,
    this.tertiary,
    this.onTertiary,
    this.tertiaryContainer,
    this.onTertiaryContainer,
    this.surface,
    this.onSurface,
    this.background,
    this.onBackground,
  });
}

/// Native blur effect settings
class NativeBlurSettings {
  final double blurRadius;
  final double saturation;
  final double opacity;
  final bool useLiquidGlass;

  const NativeBlurSettings({
    required this.blurRadius,
    required this.saturation,
    required this.opacity,
    required this.useLiquidGlass,
  });

  static const defaultSettings = NativeBlurSettings(
    blurRadius: 15.0,
    saturation: 1.0,
    opacity: 0.8,
    useLiquidGlass: false,
  );
}

/// Native theme event types
enum NativeThemeEventType {
  themeChanged,
  liquidGlassStateChanged,
}

/// Native theme change event
class NativeThemeEvent {
  final NativeThemeEventType type;
  final int? accentColor;
  final bool? liquidGlassEnabled;

  NativeThemeEvent({
    required this.type,
    this.accentColor,
    this.liquidGlassEnabled,
  });
}
