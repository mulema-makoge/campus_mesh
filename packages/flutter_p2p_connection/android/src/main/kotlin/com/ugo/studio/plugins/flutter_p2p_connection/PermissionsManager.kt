package com.ugo.studio.plugins.flutter_p2p_connection

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

import com.ugo.studio.plugins.flutter_p2p_connection.Constants
import io.flutter.plugin.common.MethodChannel


class PermissionsManager(private val applicationContext: Context) {

    private var activity: Activity? = null
    private val TAG = Constants.TAG

    fun updateActivity(activity: Activity?) {
        this.activity = activity
    }

    fun hasP2pPermissions(): Boolean {
        val fineLocationGranted = ContextCompat.checkSelfPermission(
            applicationContext, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val changeWifiStateGranted = ContextCompat.checkSelfPermission(
            applicationContext, Manifest.permission.CHANGE_WIFI_STATE
        ) == PackageManager.PERMISSION_GRANTED

        var nearbyWifiGranted = true // Assume true for older APIs
        // Only require NEARBY_WIFI_DEVICES on Android 13 (API 33) and above
        // Android 12 (API 31/32) uses ACCESS_FINE_LOCATION instead
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val targetsApi33OrHigher = applicationContext.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.TIRAMISU
            if (targetsApi33OrHigher) {
                nearbyWifiGranted = ContextCompat.checkSelfPermission(
                    applicationContext, Manifest.permission.NEARBY_WIFI_DEVICES
                ) == PackageManager.PERMISSION_GRANTED
            }
        }

        return fineLocationGranted && changeWifiStateGranted && nearbyWifiGranted
    }

    @SuppressLint("MissingPermission")
    fun hasBluetoothConnectPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val targetsApi31OrHigher = applicationContext.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.S
            if (targetsApi31OrHigher) {
                ContextCompat.checkSelfPermission(
                    applicationContext, Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
        } else {
            true
        }
    }

    fun checkP2pPermissions(result: MethodChannel.Result) {
        Log.d(TAG, "Checking Permissions (FINE_LOCATION, CHANGE_WIFI_STATE, NEARBY_WIFI_DEVICES if needed).")
        result.success(hasP2pPermissions())
    }

    fun askP2pPermissions(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to request permissions", null)
            return
        }
        val permissionsToRequest = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.CHANGE_WIFI_STATE) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.CHANGE_WIFI_STATE)
        }
        // Only request NEARBY_WIFI_DEVICES on Android 13 (API 33) and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val targetsApi33OrHigher = applicationContext.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.TIRAMISU
            if (targetsApi33OrHigher && ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }

        if (permissionsToRequest.isEmpty()) {
            Log.d(TAG, "P2P Permissions already granted.")
            result.success(true)
            return
        }
        Log.d(TAG, "Requesting P2P permissions: ${permissionsToRequest.joinToString()}")
        ActivityCompat.requestPermissions(
            currentActivity,
            permissionsToRequest.toTypedArray(),
            Constants.LOCATION_PERMISSION_REQUEST_CODE
        )
        result.success(true)
    }
}