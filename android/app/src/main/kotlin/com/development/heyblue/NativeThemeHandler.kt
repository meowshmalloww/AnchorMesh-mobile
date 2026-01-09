package com.development.heyblue

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handler for Android Material You dynamic theming and native elements.
 *
 * Material You (Android 12+) provides dynamic color theming based on
 * the user's wallpaper, creating a personalized system-wide color palette.
 *
 * This handler provides:
 * - Method channel communication with Flutter
 * - System accent color extraction
 * - Material You palette generation
 * - Dynamic color application
 */
class NativeThemeHandler(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "NativeThemeHandler"
        const val METHOD_CHANNEL = "com.project_flutter/liquid_glass"
        const val EVENT_CHANNEL = "com.project_flutter/liquid_glass_events"
    }

    private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> {
                result.success(getCapabilities())
            }

            "applyLiquidGlass" -> {
                // Liquid Glass is iOS only, but we handle the call gracefully
                Log.d(TAG, "Liquid Glass requested on Android - using Material You fallback")
                result.success(false)
            }

            "removeLiquidGlass" -> {
                result.success(false)
            }

            "applyGlobalLiquidGlassConfig" -> {
                result.success(false)
            }

            "isReducedTransparencyEnabled" -> {
                // Android doesn't have this exact setting
                result.success(false)
            }

            "applyMaterialYou" -> {
                val seedColor = call.argument<Int>("seedColor")
                result.success(applyMaterialYou(seedColor))
            }

            "getSystemAccentColor" -> {
                result.success(getSystemAccentColor())
            }

            "getMaterialYouPalette" -> {
                result.success(getMaterialYouPalette())
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Get platform capabilities
     */
    private fun getCapabilities(): Map<String, Any?> {
        return mapOf(
            "liquidGlassSupported" to false, // iOS only
            "materialYouSupported" to isMaterialYouSupported(),
            "systemAccentColor" to getSystemAccentColor(),
            "reduceTransparencyEnabled" to false,
            "reduceMotionEnabled" to isReduceMotionEnabled()
        )
    }

    /**
     * Check if Material You is supported (Android 12+)
     */
    private fun isMaterialYouSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    }

    /**
     * Check if reduce motion is enabled
     */
    private fun isReduceMotionEnabled(): Boolean {
        return try {
            val duration = android.provider.Settings.Global.getFloat(
                context.contentResolver,
                android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
                1.0f
            )
            duration == 0f
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get the system accent color
     */
    private fun getSystemAccentColor(): Int? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ - Use dynamic colors
                val colorPrimary = context.getColor(android.R.color.system_accent1_500)
                colorPrimary
            } else {
                // Fallback for older Android versions
                // Use the colorPrimary from theme
                val typedArray = context.obtainStyledAttributes(intArrayOf(android.R.attr.colorPrimary))
                val color = typedArray.getColor(0, Color.BLUE)
                typedArray.recycle()
                color
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting system accent color: ${e.message}")
            Color.BLUE
        }
    }

    /**
     * Apply Material You theming
     */
    private fun applyMaterialYou(seedColor: Int?): Boolean {
        if (!isMaterialYouSupported()) {
            Log.d(TAG, "Material You not supported on this device")
            return false
        }

        try {
            // Material You is automatically applied system-wide on Android 12+
            // We can notify Flutter about the current colors
            notifyThemeChanged()
            Log.d(TAG, "Material You applied successfully")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error applying Material You: ${e.message}")
            return false
        }
    }

    /**
     * Get the full Material You color palette
     */
    @RequiresApi(Build.VERSION_CODES.S)
    private fun getMaterialYouPaletteS(): Map<String, Int?> {
        return try {
            mapOf(
                // Primary colors
                "primary" to context.getColor(android.R.color.system_accent1_500),
                "onPrimary" to context.getColor(android.R.color.system_accent1_0),
                "primaryContainer" to context.getColor(android.R.color.system_accent1_100),
                "onPrimaryContainer" to context.getColor(android.R.color.system_accent1_900),

                // Secondary colors
                "secondary" to context.getColor(android.R.color.system_accent2_500),
                "onSecondary" to context.getColor(android.R.color.system_accent2_0),
                "secondaryContainer" to context.getColor(android.R.color.system_accent2_100),
                "onSecondaryContainer" to context.getColor(android.R.color.system_accent2_900),

                // Tertiary colors
                "tertiary" to context.getColor(android.R.color.system_accent3_500),
                "onTertiary" to context.getColor(android.R.color.system_accent3_0),
                "tertiaryContainer" to context.getColor(android.R.color.system_accent3_100),
                "onTertiaryContainer" to context.getColor(android.R.color.system_accent3_900),

                // Neutral colors
                "surface" to context.getColor(android.R.color.system_neutral1_10),
                "onSurface" to context.getColor(android.R.color.system_neutral1_900),
                "background" to context.getColor(android.R.color.system_neutral1_10),
                "onBackground" to context.getColor(android.R.color.system_neutral1_900)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting Material You palette: ${e.message}")
            emptyMap()
        }
    }

    private fun getMaterialYouPalette(): Map<String, Int?>? {
        if (!isMaterialYouSupported()) {
            return null
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getMaterialYouPaletteS()
        } else {
            null
        }
    }

    /**
     * Notify Flutter about theme changes
     */
    private fun notifyThemeChanged() {
        val accentColor = getSystemAccentColor()
        sendEvent("themeChanged", mapOf("accentColor" to accentColor))
    }

    /**
     * Send event to Flutter
     */
    private fun sendEvent(type: String, data: Map<String, Any?>) {
        eventSink?.success(mapOf("type" to type, "data" to data))
    }

    /**
     * Check if dark mode is enabled
     */
    fun isDarkModeEnabled(): Boolean {
        val nightModeFlags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightModeFlags == Configuration.UI_MODE_NIGHT_YES
    }

    /**
     * Get contrast level (high contrast mode)
     */
    fun getContrastLevel(): Float {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.resources.configuration.fontScale // Use font scale as proxy
        } else {
            1.0f
        }
    }
}
