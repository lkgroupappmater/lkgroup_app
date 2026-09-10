package com.lkgrouptrading.app

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var updateManager: AppUpdateManager? = null
    private var updateChannel: MethodChannel? = null
    private val updateListener = InstallStateUpdatedListener { state ->
        val status = when (state.installStatus()) {
            InstallStatus.DOWNLOADED -> "ready"
            InstallStatus.DOWNLOADING, InstallStatus.PENDING -> "downloading"
            InstallStatus.CANCELED, InstallStatus.FAILED -> "available"
            else -> null
        }
        if (status != null) updateChannel?.invokeMethod("updateStatus", status)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = AppUpdateManagerFactory.create(this)
        updateManager = manager
        manager.registerListener(updateListener)
        updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.lkgrouptrading.app/updates"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method !in setOf("check", "download", "install")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                manager.appUpdateInfo.addOnSuccessListener { info ->
                    when (call.method) {
                        "check" -> result.success(statusOf(info))
                        "install" -> {
                            if (info.installStatus() != InstallStatus.DOWNLOADED) {
                                result.error("not_ready", "Update is not downloaded", null)
                            } else {
                                // Called only after the user chooses to restart.
                                manager.completeUpdate()
                                    .addOnSuccessListener { result.success("ready") }
                                    .addOnFailureListener {
                                        result.error("install_failed", it.message, null)
                                    }
                            }
                        }
                        "download" -> {
                            if (statusOf(info) != "available") {
                                result.success(statusOf(info))
                            } else {
                                manager.startUpdateFlow(
                                    info,
                                    this,
                                    AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build()
                                ).addOnSuccessListener { code ->
                                    result.success(if (code == Activity.RESULT_OK) "downloading" else "available")
                                }.addOnFailureListener {
                                    result.error("download_failed", it.message, null)
                                }
                            }
                        }
                    }
                }.addOnFailureListener {
                    // Includes APKs not owned/installed through Google Play.
                    result.error("play_update_unavailable", it.message, null)
                }
            }
        }
    }

    private fun statusOf(info: AppUpdateInfo): String = when {
        info.installStatus() == InstallStatus.DOWNLOADED -> "ready"
        info.installStatus() == InstallStatus.DOWNLOADING ||
            info.installStatus() == InstallStatus.PENDING -> "downloading"
        info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
            info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE) -> "available"
        else -> "unavailable"
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updateManager?.unregisterListener(updateListener)
        updateChannel?.setMethodCallHandler(null)
        updateChannel = null
        updateManager = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
