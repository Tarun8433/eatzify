package com.zynthovo.eatzify

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ElevationGainedRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.SpeedRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * A FRAGMENT activity, not the template's `FlutterActivity`. The `health` plugin asks Health Connect
 * for permission through `registerForActivityResult`, which needs a `ComponentActivity`; from a plain
 * `FlutterActivity` the request fails at the cast and the permission sheet never appears.
 *
 * D-268: it also answers `eatzify/health_extras` — walking speed, elevation gained and floors
 * climbed per diary window, which the plugin cannot total. Read only, through Health Connect's own
 * aggregate, so a phone and a watch are de-duplicated the same way steps are.
 */
class MainActivity : FlutterFragmentActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pendingRequest: MethodChannel.Result? = null

    private val speed = HealthPermission.getReadPermission(SpeedRecord::class)
    private val elevation = HealthPermission.getReadPermission(ElevationGainedRecord::class)
    private val floors = HealthPermission.getReadPermission(FloorsClimbedRecord::class)
    private val extras = setOf(speed, elevation, floors)

    // Registered at construction: an activity-result launcher must exist before the activity starts.
    private val requestExtras =
        registerForActivityResult(PermissionController.createRequestPermissionResultContract()) {
            granted ->
            pendingRequest?.success(granted.any { it in extras })
            pendingRequest = null
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eatzify/health_extras")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> scope.launch {
                        result.success(runCatching { granted().isNotEmpty() }.getOrDefault(false))
                    }
                    "requestPermission" -> {
                        // A second request while the sheet is up would leave the first unanswered.
                        if (pendingRequest != null) return@setMethodCallHandler result.success(false)
                        pendingRequest = result
                        runCatching { requestExtras.launch(extras) }.onFailure {
                            pendingRequest = null
                            result.success(false)
                        }
                    }
                    "read" -> {
                        val windows = call.argument<List<List<Number>>>("windows").orEmpty()
                        scope.launch {
                            runCatching { read(windows) }
                                .onSuccess { result.success(it) }
                                .onFailure { result.error("UNAVAILABLE", it.javaClass.simpleName, null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun client() = HealthConnectClient.getOrCreate(this)

    private suspend fun granted(): Set<String> =
        client().permissionController.getGrantedPermissions().intersect(extras)

    /** One map per window. A value nothing recorded is null, never zero. */
    private suspend fun read(windows: List<List<Number>>): List<Map<String, Double?>> {
        val allowed = granted()
        if (allowed.isEmpty()) return windows.map { emptyMap() }
        val metrics = buildSet {
            if (speed in allowed) add(SpeedRecord.SPEED_AVG)
            if (elevation in allowed) add(ElevationGainedRecord.ELEVATION_GAINED_TOTAL)
            if (floors in allowed) add(FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL)
        }
        val client = client()
        return windows.map { (start, end) ->
            val day = client.aggregate(
                AggregateRequest(
                    metrics = metrics,
                    timeRangeFilter = TimeRangeFilter.between(
                        Instant.ofEpochMilli(start.toLong()),
                        Instant.ofEpochMilli(end.toLong()),
                    ),
                ),
            )
            mapOf(
                "speed_m_s" to day[SpeedRecord.SPEED_AVG]?.inMetersPerSecond,
                "elevation_m" to day[ElevationGainedRecord.ELEVATION_GAINED_TOTAL]?.inMeters,
                "floors" to day[FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL],
            )
        }
    }
}
