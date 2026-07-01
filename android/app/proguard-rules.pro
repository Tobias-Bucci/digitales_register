# Required by flutter_local_notifications <= 18.x because the plugin
# deserializes scheduled notifications via Gson TypeToken on Android.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Required for androidx.work compatibility with 16 KB page size devices
# Prevents aggressive shrinking of WorkDatabase_Impl and related classes
-keep class androidx.work.impl.WorkDatabase_Impl { 
    <init>();
    *;
}
-keep class androidx.work.impl.WorkDatabase {
    <init>();
    *;
}
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.** { *; }
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
    *;
}
-keepclassmembers class androidx.work.impl.WorkManagerImplExtKt {
    *;
}
-keepclassmembers class androidx.work.WorkManager {
    *;
}
-keepclassmembers class androidx.work.impl.WorkManagerImpl {
    *;
}

# Room Database support - prevent aggressive shrinking of generated DB implementations
-keep class androidx.room.Room { *; }
-keep class androidx.room.RoomDatabase { *; }
-keep class androidx.room.RoomDatabase$Builder { *; }
-keep class * extends androidx.room.RoomDatabase
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
    *;
}

# androidx.startup initializers
-keep class androidx.startup.** { *; }
-keepclassmembers class androidx.startup.** {
    <init>();
    *;
}
-keep class androidx.work.WorkManagerInitializer { *; }

# Keep all database generated classes
-keep class androidx.work.impl.WorkDatabase_Impl$** { *; }

-dontwarn androidx.work.**
-dontwarn androidx.room.**
