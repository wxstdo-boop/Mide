package com.example.mide

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingApkPath: String? = null

    /// Signing certificate of the *installed* app. An update must be signed by
    /// the same key; Android enforces this too, but checking first turns a
    /// confusing "App not installed" into a clear error.
    private val ownSigner: String? by lazy {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                ).signingInfo?.apkContentsSigners?.firstOrNull()
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                ).signatures?.firstOrNull()
            }?.toByteArray()?.let { sha256Hex(it) }
        }.getOrNull()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mide/update_installer"
        ).setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_path", "APK path is missing", null)
                return@setMethodCallHandler
            }

            val apk = File(path)
            if (!apk.isFile) {
                result.error("missing_apk", "Downloaded APK was not found", null)
                return@setMethodCallHandler
            }

            // Fail closed: an APK we cannot parse is exactly the case the
            // check exists for (truncated download, repacked file), so it must
            // not fall through to the installer.
            val apkSigner = apkSignerHex(apk)
            if (apkSigner == null) {
                result.error(
                    "signature_unreadable",
                    "Не удалось прочитать подпись APK — установка отменена",
                    null
                )
                return@setMethodCallHandler
            }
            val expectedSigner = ownSigner
            if (expectedSigner != null && apkSigner != expectedSigner) {
                result.error(
                    "signature_mismatch",
                    "APK подписан другим ключом — установка отменена",
                    null
                )
                return@setMethodCallHandler
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {
                    pendingApkPath = apk.absolutePath
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        )
                    )
                } else {
                    openApk(apk)
                }
                result.success(null)
            } catch (error: Exception) {
                result.error("installer_failed", error.message, null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val path = pendingApkPath ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        ) {
            pendingApkPath = null
            try {
                openApk(File(path))
            } catch (error: Exception) {
                Log.e("MideUpdater", "Could not open downloaded APK", error)
            }
        }
    }

    /// SHA-256 of the first signing certificate inside [apk], or null when the
    /// file cannot be parsed as a package (e.g. a corrupt download).
    private fun apkSignerHex(apk: File): String? = runCatching {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageArchiveInfo(
                apk.absolutePath,
                PackageManager.GET_SIGNING_CERTIFICATES
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(
                apk.absolutePath,
                PackageManager.GET_SIGNATURES
            )
        } ?: return null

        val certBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.firstOrNull()?.toByteArray()
        }
        certBytes?.let { sha256Hex(it) }
    }.getOrNull()

    private fun sha256Hex(bytes: ByteArray): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun openApk(apk: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            apk
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
