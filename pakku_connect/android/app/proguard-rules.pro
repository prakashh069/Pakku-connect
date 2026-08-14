# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Connecto Services and Receivers
-keep class com.pakku.pakku_connect.** { *; }
-keep class com.pakku.pakku_connect.PhoneStateService { *; }
-keep class com.pakku.pakku_connect.MainActivity { *; }
-keep class com.pakku.pakku_connect.CallStateReceiver { *; }
-keep class com.pakku.pakku_connect.SMSReceiver { *; }

# MethodChannels and JNI bindings
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel$MethodCallHandler *;
    @io.flutter.plugin.common.EventChannel$StreamHandler *;
}

# Android annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Suppress warnings for Play Store Core deferred components
-dontwarn com.google.android.play.core.**
