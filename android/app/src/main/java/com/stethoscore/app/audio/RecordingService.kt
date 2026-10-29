package com.stethoscore.app.audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import com.stethoscore.app.MainActivity

/**
 * The foreground service a lecture records in (T0146 item 3), of type
 * microphone, so it goes on in the background and with the screen off.
 *
 * Its ongoing notification: "Recording" with a chronometer counting up from
 * the start (the banked time included), and Pause/Resume and Stop. It is
 * VISIBILITY_PRIVATE with a public version that says only "Recording", so the
 * lecture's name is never on the lock screen. Started only from the app in
 * front (Android 14's while-in-use rule for the microphone): tiles and
 * shortcuts open the activity first.
 */
class RecordingService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var stopListening: (() -> Unit)? = null
    private var modeListener: Any? = null
    private var focus: AudioFocusRequest? = null
    private var callListener: PhoneStateListener? = null

    private val recorder: LectureRecorder get() = LectureRecorder.shared(this)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                // in front at once (startForegroundService's deadline), then again once
                // recording, so the foreground notification carries the running clock
                goForeground()
                if (!recorder.state.isActive && !recorder.start()) { finish(); return START_NOT_STICKY }
                goForeground()
                watch()
            }
            ACTION_PAUSE -> recorder.pause()
            ACTION_RESUME -> recorder.resume()
            ACTION_STOP -> { stopRecording(); return START_NOT_STICKY }
        }
        if (recorder.state.isActive) notifyNow()
        return START_NOT_STICKY
    }

    private fun goForeground() {
        val notification = build(this, recorder)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(NOTIFICATION_ID, notification)
    }

    private fun notifyNow() {
        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, build(this, recorder))
    }

    private fun watch() {
        if (stopListening != null) return
        // a failure (the microphone lost) ends the service; the recorder hands its file on
        stopListening = recorder.listen { state -> if (state.isActive) notifyNow() else if (state is RecorderState.Failed) finish() }
        val audio = getSystemService(AudioManager::class.java)
        // a call takes the microphone: paused, and it stays paused. Android 12+ says so by the audio mode;
        // before it, by the phone's call state (LISTEN_CALL_STATE needs no permission there)
        if (sdk() >= 31) {
            val listener = AudioManager.OnModeChangedListener { mode -> if (inCall(mode)) main.post { recorder.interrupt(RecorderWords.callPaused) } }
            audio?.addOnModeChangedListener(mainExecutor, listener)
            modeListener = listener
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    if (state != TelephonyManager.CALL_STATE_IDLE) main.post { recorder.interrupt(RecorderWords.callPaused) }
                }
            }
            @Suppress("DEPRECATION")
            getSystemService(TelephonyManager::class.java)?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            callListener = listener
        }
        // audio focus, on every version: another app taking it pauses the recording (a call, when one is ringing)
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener({ change -> focusChanged(change, audio) }, main)
            .build()
        focus = request
        // refused (a call holds it): paused at once, as a loss would
        if (audio != null && audio.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            focusChanged(AudioManager.AUDIOFOCUS_LOSS, audio)
        main.postDelayed(diskCheck, DISK_CHECK_MS)
    }

    private fun focusChanged(change: Int, audio: AudioManager?) {
        if (change != AudioManager.AUDIOFOCUS_LOSS && change != AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) return
        val calling = audio?.let { inCall(it.mode) } == true ||
            (sdk() < 31 && runCatching { @Suppress("DEPRECATION") getSystemService(TelephonyManager::class.java)?.callState }.getOrNull()
                .let { it != null && it != TelephonyManager.CALL_STATE_IDLE })
        recorder.interrupt(if (calling) RecorderWords.callPaused else RecorderWords.focusLost)
    }

    private fun inCall(mode: Int) = mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION || mode == AudioManager.MODE_RINGTONE

    private val diskCheck = object : Runnable {
        override fun run() {
            if (!recorder.state.isActive) return
            if (recorder.diskTooLow()) {
                recorder.note = RecorderWords.lowDisk
                stopRecording()
                return
            }
            main.postDelayed(this, DISK_CHECK_MS)
        }
    }

    private fun stopRecording() {
        val file = recorder.stop()
        finish()
        if (file != null) LectureRecorder.finished(file)
    }

    private fun finish() {
        unwatch()
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    private fun unwatch() {
        stopListening?.invoke(); stopListening = null
        main.removeCallbacks(diskCheck)
        val audio = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= 31) (modeListener as? AudioManager.OnModeChangedListener)?.let { audio?.removeOnModeChangedListener(it) }
        modeListener = null
        callListener?.let { @Suppress("DEPRECATION") getSystemService(TelephonyManager::class.java)?.listen(it, PhoneStateListener.LISTEN_NONE) }
        callListener = null
        focus?.let { audio?.abandonAudioFocusRequest(it) }
        focus = null
    }

    override fun onDestroy() {
        unwatch()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.stethoscore.app.record.START"
        const val ACTION_PAUSE = "com.stethoscore.app.record.PAUSE"
        const val ACTION_RESUME = "com.stethoscore.app.record.RESUME"
        const val ACTION_STOP = "com.stethoscore.app.record.STOP"
        const val CHANNEL_ID = "lecture-recording"
        const val NOTIFICATION_ID = 4601
        private const val DISK_CHECK_MS = 5_000L

        /** The API level the call and focus watch is chosen by; tests set an older one. */
        @Volatile internal var sdk: () -> Int = { Build.VERSION.SDK_INT }

        fun intent(context: Context, action: String): Intent = Intent(context, RecordingService::class.java).setAction(action)

        /** Start recording: call only from the app in front. */
        fun start(context: Context) {
            val i = intent(context, ACTION_START)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
        }

        fun send(context: Context, action: String) { context.startService(intent(context, action)) }

        fun channel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, context.getString(com.stethoscore.app.R.string.recorder_channel),
                NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false); lockscreenVisibility = Notification.VISIBILITY_PRIVATE })
        }

        /**
         * The ongoing notification. Recording: a chronometer counting up from
         * when it would read 0:00 (the banked time taken off), Pause and Stop.
         * Paused: the time held, Resume and Stop. Private, with a public
         * version that names nothing.
         */
        fun build(context: Context, recorder: LectureRecorder, now: Long = System.currentTimeMillis()): Notification {
            channel(context)
            val state = recorder.state
            val elapsedMs = (recorder.elapsed() * 1000).toLong()
            val res = context.resources
            val recordingWord = res.getString(com.stethoscore.app.R.string.recorder_recording)
            val title = when (state) {
                is RecorderState.Paused -> res.getString(pausedWord(state.reason)) + " · " + RecorderNames.clock(recorder.elapsed())
                else -> recordingWord
            }
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
            fun action(word: Int, act: String, icon: Int): Notification.Action =
                Notification.Action.Builder(Icon.createWithResource(context, icon), res.getString(word),
                    PendingIntent.getService(context, act.hashCode(), intent(context, act), PendingIntent.FLAG_IMMUTABLE)).build()
            val counting = state.isRecording
            val publicVersion = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle(recordingWord)
                .setUsesChronometer(counting).setShowWhen(counting).setWhen(now - elapsedMs)
                .setCategory(Notification.CATEGORY_SERVICE)
                .build()
            val builder = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle(title)
                .setContentText(RecorderNames.defaultTitle(recorder.moment, res.configuration.locales[0].language))
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setShowWhen(counting)
                .setUsesChronometer(counting)
                .setWhen(now - elapsedMs)
            if (Build.VERSION.SDK_INT >= 24) builder.setChronometerCountDown(false)
            if (counting) builder.addAction(action(com.stethoscore.app.R.string.recorder_pause, ACTION_PAUSE, android.R.drawable.ic_media_pause))
            else builder.addAction(action(com.stethoscore.app.R.string.recorder_resume, ACTION_RESUME, android.R.drawable.ic_media_play))
            builder.addAction(action(com.stethoscore.app.R.string.recorder_stop, ACTION_STOP, android.R.drawable.ic_menu_close_clear_cancel))
            if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            return builder.build()
        }

        /** The resource for a pause's line: by a call, by another app's sound or microphone, or the student's own. */
        fun pausedWord(reason: String?): Int = when (reason) {
            null -> com.stethoscore.app.R.string.recorder_paused
            RecorderWords.micTaken -> com.stethoscore.app.R.string.recorder_mic_taken
            RecorderWords.focusLost -> com.stethoscore.app.R.string.recorder_focus_lost
            else -> com.stethoscore.app.R.string.recorder_call_paused
        }

        /** The resource for a failure's reason this recorder wrote, or null for a system message. */
        fun failedWord(reason: String): Int? = when (reason) {
            RecorderWords.micLost -> com.stethoscore.app.R.string.recorder_mic_lost
            RecorderWords.nothingRecorded -> com.stethoscore.app.R.string.recorder_nothing_recorded
            else -> null
        }

        /** The notification's tap: opens the app on the recorder. */
        const val ACTION_OPEN = "com.stethoscore.app.record.OPEN"
    }
}
