# 百度地图SDK保护规则
-keep class com.baidu.** {*;}
-dontwarn com.baidu.**

# 核心组件
-keep class com.baidu.mapapi.** {*;}
-keep class com.baidu.platform.** {*;}
-keep class com.baidu.location.** {*;}
-keep class com.baidu.geofence.** {*;}
-keep class com.baidu.bmfmap.** {*;}

# 搜索相关组件（关键）
-keep class com.baidu.mapapi.search.** {*;}
-keep class com.baidu.mapapi.search.utils.** {*;}
-keep class com.baidu.mapapi.search.handlers.** {*;}

# Gson相关保护（必须添加）
-keep class com.google.gson.** {*;}
-keep class com.google.gson.reflect.** {*;}
-keepattributes Signature
-keepattributes *Annotation*

# 保持所有构造函数和方法不被混淆
-keepclassmembers class * {
    public void set*(***);
    public *** get*();
    public *** is*();
}

# Flutter插件保护
-keep class io.flutter.plugin.** {*;}

# 小米推送
-keep class com.xiaomi.** { *; }
-dontwarn com.xiaomi.push.**

# VIVO推送
-keep class com.vivo.** { *; }
-dontwarn com.vivo.push.**

# OPPO推送
-keep class com.heytap.** { *; }
-dontwarn com.heytap.**

# 魅族推送
-dontwarn com.meizu.cloud.pushsdk.**
-keep class com.meizu.cloud.** {*;}

# 环信推送
-keep class com.hyphenate.** {*;}
-dontwarn  com.hyphenate.**

# 特定类忽略
-dontwarn com.google.gson.**
