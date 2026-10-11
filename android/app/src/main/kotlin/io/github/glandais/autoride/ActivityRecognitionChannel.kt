package io.github.glandais.autoride

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The activity Google Play services recognises — on a bicycle, in a vehicle, on
 * foot, still — forwarded to Dart for the audit log (T055).
 *
 * The Android half of `ios/Runner/AutoRideActivityRecognition.swift`, speaking
 * the same vocabulary so one reader serves both logs. Like it, **it decides
 * nothing**: activities leave as journal lines only.
 *
 * Never asks for the permission. `requestActivityUpdates` without it throws a
 * SecurityException; the runtime prompt is raised from the settings screen,
 * through permission_handler, and a session that starts without the grant
 * only reports that it did not start.
 */
class ActivityRecognitionChannel(
    messenger: BinaryMessenger,
    private val context: Context,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var running = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start((call.argument<Number>("intervalMs") ?: 10_000).toLong(), result)
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        instance = this
    }

    /**
     * Answers `granted` once updates are requested, or the reason nothing was
     * started (`denied`, `unavailable`). A failure of the request itself comes
     * back as an error, which the Dart side journals.
     */
    private fun start(intervalMs: Long, result: MethodChannel.Result) {
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) !=
            ConnectionResult.SUCCESS
        ) {
            return result.success("unavailable")
        }
        if (!hasPermission()) return result.success("denied")
        if (running) return result.success("granted")

        try {
            ActivityRecognition.getClient(context)
                .requestActivityUpdates(intervalMs, pendingIntent())
                .addOnSuccessListener {
                    running = true
                    result.success("granted")
                }
                .addOnFailureListener { e -> result.error("request", e.message, null) }
        } catch (e: SecurityException) {
            result.success("denied")
        }
    }

    private fun stop() {
        if (!running) return
        running = false
        try {
            ActivityRecognition.getClient(context).removeActivityUpdates(pendingIntent())
        } catch (_: SecurityException) {
            // The grant was revoked while running: the updates are already gone.
        }
    }

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED

    /** The same PendingIntent for request and removal, or removal matches nothing. */
    private fun pendingIntent(): PendingIntent {
        // Mutable: Play services fills the result into the intent's extras.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, ActivityRecognitionReceiver::class.java),
            flags,
        )
    }

    fun deliver(result: ActivityRecognitionResult) {
        channel.invokeMethod("onActivity", describe(result))
    }

    companion object {
        /** Shared with `activity_recognition_session.dart`. */
        const val CHANNEL_NAME = "dev.glandais.autoride/activity"

        private const val REQUEST_CODE = 5501

        /**
         * Below this a probable activity is noise and is not carried in `o`.
         * Play services reports every candidate, most of them in single digits.
         */
        private const val OTHER_MIN_CONFIDENCE = 25

        /**
         * The live channel, or null when no engine is attached — an update
         * arriving then is dropped, exactly as an iOS one is.
         */
        var instance: ActivityRecognitionChannel? = null
            private set

        /**
         * One result in the vocabulary shared with iOS: `k` the most probable
         * kind, `o` the other kinds Play services rates at
         * [OTHER_MIN_CONFIDENCE] % or more, `cf` the confidence band and `pc`
         * the percentage it was banded from, `at` the result's time (ms).
         */
        fun describe(result: ActivityRecognitionResult): Map<String, Any> {
            val primary = result.mostProbableActivity
            val kind = kindOf(primary.type)
            val others = result.probableActivities
                .filter { it.confidence >= OTHER_MIN_CONFIDENCE }
                .map { kindOf(it.type) }
                .filter { it != kind }
                .distinct()

            val payload = mutableMapOf<String, Any>(
                "k" to kind,
                "cf" to band(primary.confidence),
                "pc" to primary.confidence,
                "at" to result.time,
            )
            if (others.isNotEmpty()) payload["o"] = others
            return payload
        }

        private fun kindOf(type: Int): String = when (type) {
            DetectedActivity.ON_BICYCLE -> "bike"
            DetectedActivity.IN_VEHICLE -> "car"
            DetectedActivity.RUNNING -> "run"
            DetectedActivity.WALKING -> "walk"
            // Android's parent of walking and running; iOS has no equivalent.
            DetectedActivity.ON_FOOT -> "foot"
            DetectedActivity.STILL -> "still"
            DetectedActivity.TILTING -> "tilt"
            else -> "unknown"
        }

        /** iOS reports bands, Android percentages: band them the same way. */
        private fun band(confidence: Int): String = when {
            confidence >= 75 -> "high"
            confidence >= 50 -> "medium"
            else -> "low"
        }
    }
}
