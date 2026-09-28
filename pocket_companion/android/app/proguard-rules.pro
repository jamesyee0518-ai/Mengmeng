# DJI Mobile SDK V4 混淆规则（依据官方 Sample Code/app/proguard-rules.pro 精简）
-keepattributes Exceptions,InnerClasses,*Annotation*,Signature,EnclosingMethod

-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn dji.**
-dontwarn com.dji.**
-dontwarn sun.**
-dontwarn okhttp3.**
-dontwarn retrofit2.**

-keepclassmembers enum * {
    public static <methods>;
}

-keep class dji.** { *; }
-keep class com.dji.** { *; }
-keep class org.bouncycastle.** { *; }
-keep class com.squareup.wire.** { *; }
-keep class net.sqlcipher.** { *; }
-keep class org.greenrobot.eventbus.** { *; }
-keep class com.lmax.disruptor.** { *; }
-keep class it.sauronsoftware.ftp4j.** { *; }
-keep class com.cySdkyc.** { *; }

-keepclasseswithmembers class * {
    native <methods>;
}

-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Android lacks java.lang.management; referenced only from DJI-bundled disruptor diagnostics
-dontwarn java.lang.management.**
