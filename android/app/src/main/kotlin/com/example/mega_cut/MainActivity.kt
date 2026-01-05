package com.example.mega_cut

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.example.mega_cut/permissions"
	private var pendingResult: MethodChannel.Result? = null
	private val REQUEST_CODE = 555

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			if (call.method == "requestAndroid13Permissions") {
				if (pendingResult != null) {
					result.error("IN_PROGRESS", "Permission request already in progress", null)
					return@setMethodCallHandler
				}

				if (android.os.Build.VERSION.SDK_INT < 33) {
					result.success(true)
					return@setMethodCallHandler
				}

				val needed = ArrayList<String>()
				if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) != PackageManager.PERMISSION_GRANTED) {
					needed.add(Manifest.permission.READ_MEDIA_AUDIO)
				}
				if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED) {
					needed.add(Manifest.permission.READ_MEDIA_VIDEO)
				}

				if (needed.isEmpty()) {
					result.success(true)
				} else {
					pendingResult = result
					ActivityCompat.requestPermissions(this, needed.toTypedArray(), REQUEST_CODE)
				}
			} else {
				result.notImplemented()
			}
		}
	}

	override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode == REQUEST_CODE) {
			val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
			pendingResult?.success(allGranted)
			pendingResult = null
		}
	}
}
