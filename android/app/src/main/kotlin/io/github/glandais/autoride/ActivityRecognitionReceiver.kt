package io.github.glandais.autoride

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityRecognitionResult

/**
 * Where Play services delivers activity updates (T055). It only hands them to
 * the live channel; with no engine attached they are dropped.
 */
class ActivityRecognitionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityRecognitionResult.hasResult(intent)) return
        val result = ActivityRecognitionResult.extractResult(intent) ?: return
        ActivityRecognitionChannel.instance?.deliver(result)
    }
}
