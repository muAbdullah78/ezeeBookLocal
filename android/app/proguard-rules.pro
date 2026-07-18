# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Supabase / GoTrue
-keep class io.supabase.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# In-app purchase
-keep class com.android.vending.billing.** { *; }

# Speech to text
-keep class com.csdcorp.speech_to_text.** { *; }

# Keep model classes (JSON serialization)
-keepclassmembers class * {
    public <init>(...);
}

# Prevent R8 from removing classes used via reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# General Android
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
