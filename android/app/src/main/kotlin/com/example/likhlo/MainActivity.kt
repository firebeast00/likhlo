package com.example.likhlo

import android.content.Context
import android.content.Intent
import android.app.Activity
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.likhlo/quick_tile"
    private val AUDIO_CHANNEL = "com.likhlo/audio_feedback"
    private val BACKUP_CHANNEL = "com.likhlo/automatic_backup"
    private val BACKUP_REQUEST = 7410
    private val backupPreferences by lazy { getSharedPreferences("encrypted_backup_destination", Context.MODE_PRIVATE) }
    private var pendingBackup: Triple<ByteArray, String, MethodChannel.Result>? = null
    private var quickAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        quickAction = intent.getStringExtra("quick_action")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getQuickAction") {
                result.success(quickAction)
                quickAction = null
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isDeviceSilent") {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                result.success(audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                "create" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val password = call.argument<String>("password")
                    val name = call.argument<String>("name")
                    if (bytes == null || password.isNullOrEmpty() || name.isNullOrEmpty() || pendingBackup != null) {
                        result.error("backup_arguments", "A backup is already being saved or input is missing.", null)
                    } else {
                        pendingBackup = Triple(bytes, password, result)
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        try { startActivityForResult(intent, BACKUP_REQUEST) }
                        catch (error: Exception) {
                            pendingBackup = null
                            result.error("backup_picker", error.message, null)
                        }
                    }
                }
                "configuration" -> {
                    try {
                        val uri = backupPreferences.getString("uri", null)
                        val password = if (uri == null) null else readPassword()
                        result.success(if (uri != null && password != null) mapOf("password" to password) else null)
                    } catch (error: Exception) { result.error("backup_key", error.message, null) }
                }
                "overwrite" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val uri = backupPreferences.getString("uri", null)
                    if (bytes == null || uri == null) result.success(false)
                    else Thread {
                        try {
                            val document = Uri.parse(uri)
                            val previous = contentResolver.openInputStream(document)?.use { it.readBytes() }
                            try { writeDocument(document, bytes) }
                            catch (error: Exception) {
                                if (previous != null) try { writeDocument(document, previous) } catch (_: Exception) {}
                                throw error
                            }
                            runOnUiThread { result.success(true) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("backup_write", error.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Android activity result for the document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != BACKUP_REQUEST) return
        val request = pendingBackup ?: return
        pendingBackup = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) { request.third.success(false); return }
        Thread {
            try {
                contentResolver.takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                writeDocument(uri, request.first)
                val encrypted = sealPassword(request.second)
                backupPreferences.edit().putString("uri", uri.toString())
                    .putString("password", encrypted).apply()
                runOnUiThread { request.third.success(true) }
            } catch (error: Exception) {
                runOnUiThread { request.third.error("backup_save", error.message, null) }
            }
        }.start()
    }

    private fun writeDocument(uri: Uri, bytes: ByteArray) {
        contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes); it.flush() }
            ?: error("Cannot write the selected backup document")
    }

    private fun backupKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("likhlo_backup_key_v1", null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder("likhlo_backup_key_v1",
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .build())
        return generator.generateKey()
    }

    private fun sealPassword(password: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, backupKey())
        return Base64.encodeToString(cipher.iv + cipher.doFinal(password.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    private fun readPassword(): String? {
        val data = backupPreferences.getString("password", null) ?: return null
        val bytes = Base64.decode(data, Base64.NO_WRAP)
        if (bytes.size < 29) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, backupKey(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val action = intent.getStringExtra("quick_action")
        if (action != null) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("triggerAction", action)
            }
        }
    }
}
