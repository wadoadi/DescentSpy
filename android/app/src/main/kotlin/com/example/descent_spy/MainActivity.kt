package com.example.descent_spy

import android.Manifest
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.descent_spy/gps_status"
    private var locationManager: LocationManager? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var gpsLocationListener: LocationListener? = null
    private var visibleSatellites: Int? = null
    private var usedSatellites: Int? = null
    private var gpsFixAtNanos: Long? = null
    private var gpsFixAltitudeAtNanos: Long? = null
    private var activityResumed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSatelliteStatus" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                            result.success(null)
                        } else if (!hasLocationPermission()) {
                            result.error(
                                "permission_denied",
                                "Location permission is required for satellite status.",
                                null,
                            )
                        } else if (!activityResumed) {
                            result.success(null)
                        } else {
                            val registered = try {
                                ensureGnssCallback()
                            } catch (error: SecurityException) {
                                result.error(
                                    "permission_denied",
                                    "Location permission is required for satellite status.",
                                    error.message,
                                )
                                return@setMethodCallHandler
                            }
                            if (!registered) {
                                result.error(
                                    "gnss_unavailable",
                                    "Could not register GNSS status callback.",
                                    null,
                                )
                                return@setMethodCallHandler
                            }
                            val visible = visibleSatellites
                            val used = usedSatellites
                            if (visible == null || used == null) {
                                result.success(null)
                            } else {
                                result.success(
                                    mapOf(
                                        "visible" to visible,
                                        "used" to used,
                                        "is2d" to (
                                            used >= 3 && hasFreshGpsFix()
                                        ),
                                        "is3d" to (
                                            used >= 4 && hasFreshGpsAltitudeFix()
                                        ),
                                    ),
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    private fun ensureGnssCallback(): Boolean {
        if (gnssCallback != null && gpsLocationListener != null) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val callback = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                if (status.satelliteCount == 0) {
                    visibleSatellites = null
                    usedSatellites = null
                    return
                }
                var used = 0
                for (index in 0 until status.satelliteCount) {
                    if (status.usedInFix(index)) used++
                }
                visibleSatellites = status.satelliteCount
                usedSatellites = used
            }
        }
        val registered = locationManager?.registerGnssStatusCallback(
            callback,
            Handler(Looper.getMainLooper()),
        ) ?: false
        if (!registered) return false
        gnssCallback = callback
        val locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                gpsFixAtNanos = location.elapsedRealtimeNanos
                gpsFixAltitudeAtNanos = if (location.hasAltitude()) {
                    location.elapsedRealtimeNanos
                } else {
                    null
                }
            }
        }
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                3000L,
                0f,
                locationListener,
                Looper.getMainLooper(),
            )
        } catch (error: SecurityException) {
            locationManager?.unregisterGnssStatusCallback(callback)
            gnssCallback = null
            return false
        } catch (error: IllegalArgumentException) {
            locationManager?.unregisterGnssStatusCallback(callback)
            gnssCallback = null
            return false
        }
        gpsLocationListener = locationListener
        return true
    }

    private fun hasFreshGpsFix(): Boolean {
        val fixTimeNanos = gpsFixAtNanos ?: return false
        return SystemClock.elapsedRealtimeNanos() - fixTimeNanos <= 10_000_000_000L
    }

    private fun hasFreshGpsAltitudeFix(): Boolean {
        val fixTimeNanos = gpsFixAltitudeAtNanos ?: return false
        return SystemClock.elapsedRealtimeNanos() - fixTimeNanos <= 10_000_000_000L
    }

    private fun stopGnssMonitoring() {
        gpsLocationListener?.let { locationManager?.removeUpdates(it) }
        gpsLocationListener = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            gnssCallback?.let { locationManager?.unregisterGnssStatusCallback(it) }
        }
        gnssCallback = null
        visibleSatellites = null
        usedSatellites = null
        gpsFixAtNanos = null
        gpsFixAltitudeAtNanos = null
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
    }

    override fun onPause() {
        activityResumed = false
        stopGnssMonitoring()
        super.onPause()
    }

    override fun onDestroy() {
        stopGnssMonitoring()
        super.onDestroy()
    }
}
