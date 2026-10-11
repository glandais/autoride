package io.github.glandais.autoride

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // T055: the activity Play services recognises, journalled and nothing more.
        ActivityRecognitionChannel(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    }
}
