# flutter_local_notifications stores scheduled reminders as JSON through Gson. R8 strips the generic
# signatures Gson's TypeToken reads, and the boot receiver that re-schedules reminders crashes the
# release app ("TypeToken must be created with a type argument"). Rules from the plugin's README.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
