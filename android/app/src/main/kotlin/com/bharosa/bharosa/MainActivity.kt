package com.bharosa.bharosa

import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.bharosa.app/screen_protector"
    private val LOCATION_REQ_CODE = 9921
    private var pendingLocationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecure" -> {
                    runOnUiThread {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    }
                    result.success(true)
                }
                "disableSecure" -> {
                    runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "getDeviceId" -> {
                    try {
                        @android.annotation.SuppressLint("HardwareIds")
                        val androidId = android.provider.Settings.Secure.getString(
                            contentResolver,
                            android.provider.Settings.Secure.ANDROID_ID
                        )
                        result.success(androidId ?: "")
                    } catch (e: Exception) {
                        result.error("DEVICE_ID_ERROR", e.localizedMessage, null)
                    }
                }
                "checkLocationPermission" -> {
                    val fine = androidx.core.content.ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.ACCESS_FINE_LOCATION
                    )
                    val coarse = androidx.core.content.ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                    )
                    val isGranted = (fine == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                            coarse == android.content.pm.PackageManager.PERMISSION_GRANTED)
                    result.success(isGranted)
                }
                "requestLocationPermission" -> {
                    val fine = androidx.core.content.ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.ACCESS_FINE_LOCATION
                    )
                    val coarse = androidx.core.content.ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                    )
                    if (fine == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                        coarse == android.content.pm.PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        pendingLocationResult = result
                        androidx.core.app.ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                android.Manifest.permission.ACCESS_FINE_LOCATION,
                                android.Manifest.permission.ACCESS_COARSE_LOCATION
                            ),
                            LOCATION_REQ_CODE
                        )
                    }
                }
                "getLocation" -> {
                    try {
                        val locationManager = getSystemService(android.content.Context.LOCATION_SERVICE) as? android.location.LocationManager
                        var bestLocation: android.location.Location? = null
                        if (locationManager != null) {
                            val providers = locationManager.getProviders(true)
                            for (provider in providers) {
                                try {
                                    val l = locationManager.getLastKnownLocation(provider) ?: continue
                                    if (bestLocation == null || (l.hasAccuracy() && bestLocation.hasAccuracy() && l.accuracy < bestLocation.accuracy)) {
                                        bestLocation = l
                                    } else if (bestLocation == null) {
                                        bestLocation = l
                                    }
                                } catch (_: SecurityException) {}
                            }

                            // If no cached fix, request a fast one-shot update
                            if (bestLocation == null) {
                                val providerToUse = when {
                                    locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) -> android.location.LocationManager.GPS_PROVIDER
                                    locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER) -> android.location.LocationManager.NETWORK_PROVIDER
                                    else -> providers.firstOrNull()
                                }
                                if (providerToUse != null) {
                                    try {
                                        locationManager.requestSingleUpdate(
                                            providerToUse,
                                            object : android.location.LocationListener {
                                                override fun onLocationChanged(loc: android.location.Location) {}
                                                @Deprecated("Deprecated in Java")
                                                override fun onStatusChanged(p: String?, s: Int, b: android.os.Bundle?) {}
                                                override fun onProviderEnabled(p: String) {}
                                                override fun onProviderDisabled(p: String) {}
                                            },
                                            android.os.Looper.getMainLooper()
                                        )
                                    } catch (_: SecurityException) {}
                                }
                            }
                        }
                        if (bestLocation != null) {
                            var city = ""
                            var region = ""
                            var country = ""
                            try {
                                val geocoder = android.location.Geocoder(this, java.util.Locale.getDefault())
                                @Suppress("DEPRECATION")
                                val addresses = geocoder.getFromLocation(bestLocation.latitude, bestLocation.longitude, 1)
                                if (!addresses.isNullOrEmpty()) {
                                    val addr = addresses[0]
                                    city = addr.locality ?: addr.subAdminArea ?: ""
                                    region = addr.adminArea ?: ""
                                    country = addr.countryName ?: ""
                                }
                            } catch (_: Exception) {}

                            result.success(mapOf(
                                "latitude" to bestLocation.latitude,
                                "longitude" to bestLocation.longitude,
                                "accuracy" to bestLocation.accuracy.toDouble(),
                                "city" to city,
                                "region" to region,
                                "country" to country
                            ))
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.any {
                it == android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            pendingLocationResult?.success(granted)
            pendingLocationResult = null
        }
    }
}
