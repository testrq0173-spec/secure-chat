package com.bharosa.bharosa

import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.bharosa.app/screen_protector"
    private val LOCATION_REQ_CODE = 9921
    private val BACKGROUND_LOCATION_REQ_CODE = 9922
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingBackgroundResult: MethodChannel.Result? = null

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
                "checkBackgroundLocationPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                        val bg = androidx.core.content.ContextCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                        )
                        result.success(bg == android.content.pm.PackageManager.PERMISSION_GRANTED)
                    } else {
                        result.success(true)
                    }
                }
                "requestBackgroundLocationPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                        val bg = androidx.core.content.ContextCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                        )
                        if (bg == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            pendingBackgroundResult = result
                            androidx.core.app.ActivityCompat.requestPermissions(
                                this,
                                arrayOf(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                                BACKGROUND_LOCATION_REQ_CODE
                            )
                        }
                    } else {
                        result.success(true)
                    }
                }
                "openLocationSettings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = android.net.Uri.fromParts("package", packageName, null)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.localizedMessage, null)
                    }
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
                    val foregroundGranted = (fine == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                            coarse == android.content.pm.PackageManager.PERMISSION_GRANTED)

                    if (android.os.Build.VERSION.SDK_INT == android.os.Build.VERSION_CODES.Q) {
                        // Android 10: Can request foreground + background in one single dialog to show "Allow all the time"
                        pendingLocationResult = result
                        androidx.core.app.ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                android.Manifest.permission.ACCESS_FINE_LOCATION,
                                android.Manifest.permission.ACCESS_COARSE_LOCATION,
                                android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                            ),
                            LOCATION_REQ_CODE
                        )
                    } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        // Android 11+: Google requires requesting foreground first, then background separately
                        if (!foregroundGranted) {
                            pendingLocationResult = result
                            androidx.core.app.ActivityCompat.requestPermissions(
                                this,
                                arrayOf(
                                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                                ),
                                LOCATION_REQ_CODE
                            )
                        } else {
                            // Foreground is already granted, prompt for "Allow all the time" (Background)
                            val bg = androidx.core.content.ContextCompat.checkSelfPermission(
                                this,
                                android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                            )
                            if (bg == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                result.success(true)
                            } else {
                                pendingBackgroundResult = result
                                androidx.core.app.ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                                    BACKGROUND_LOCATION_REQ_CODE
                                )
                            }
                        }
                    } else {
                        // Android 9 and lower
                        if (foregroundGranted) {
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
        when (requestCode) {
            LOCATION_REQ_CODE -> {
                val granted = grantResults.isNotEmpty() && grantResults.any {
                    it == android.content.pm.PackageManager.PERMISSION_GRANTED
                }
                if (granted && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    val bgGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED

                    if (!bgGranted) {
                        // Immediately cascade to request "Allow all the time"
                        androidx.core.app.ActivityCompat.requestPermissions(
                            this,
                            arrayOf(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                            BACKGROUND_LOCATION_REQ_CODE
                        )
                    } else {
                        pendingLocationResult?.success(true)
                        pendingLocationResult = null
                    }
                } else {
                    pendingLocationResult?.success(granted)
                    pendingLocationResult = null
                }
            }
            BACKGROUND_LOCATION_REQ_CODE -> {
                val bgGranted = grantResults.isNotEmpty() && grantResults.any {
                    it == android.content.pm.PackageManager.PERMISSION_GRANTED
                }
                pendingBackgroundResult?.success(bgGranted)
                pendingBackgroundResult = null
                pendingLocationResult?.success(true)
                pendingLocationResult = null
            }
        }
    }
}
