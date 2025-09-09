package com.example.sbhidhrk_linkedn

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request default dialer on Android 10+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            requestDefaultDialer()
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun requestDefaultDialer() {
        val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
        roleManager?.let {
            if (!it.isRoleHeld(RoleManager.ROLE_DIALER)) {
                try {
                    // Try to launch system default dialer prompt
                    val intent = it.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                    startActivityForResult(intent, 1001)
                } catch (e: Exception) {
                    // If blocked by device, open Default Apps settings manually after delay
                    Handler(Looper.getMainLooper()).postDelayed({
                        openDefaultDialerSettings()
                    }, 500) // Delay 0.5 seconds
                }
            }
        }
    }

    private fun openDefaultDialerSettings() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
