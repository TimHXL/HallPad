package com.timhxl.hallbeat

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager
import kotlinx.coroutines.*

/** Owns the transport job independently of page visibility and the display lifecycle. */
internal class ScorePlaybackService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == PAUSE) { pause(this); return START_NOT_STICKY }
        val request = pending
        if (request == null) { stopSelf(startId); return START_NOT_STICKY }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "曲谱持续播放", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val pause = PendingIntent.getService(this, 1, Intent(this, ScorePlaybackService::class.java).setAction(PAUSE), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play).setContentTitle(request.title)
            .setContentText("正在通过 HallPad 播放").setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "暂停", pause).build()).build()
        try {
            startForeground(4107, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            if (wakeLock == null) wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:scorePlayback").apply { acquire() }
            launchRequest(request) { if (pending === request) { pending = null; stopSelf(startId) } }
        } catch (error: Exception) {
            request.onError("后台播放服务启动失败：${error.message ?: error.javaClass.simpleName}"); request.onStop(); pending = null; stopSelf(startId)
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        if (pending?.remote == true) { pending?.onStop(); pending = null; job?.cancel() }
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        super.onDestroy()
    }
    companion object {
        private const val CHANNEL = "hallpad_score_playback"
        private const val PAUSE = "com.timhxl.hallbeat.PAUSE_SCORE"
        private data class Request(val title: String, val remote: Boolean, val onStop: () -> Unit, val onError: (String) -> Unit, val block: suspend () -> Unit)
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        private var pending: Request? = null
        private var job: Job? = null
        val playing: Boolean get() = pending != null
        private fun launchRequest(request: Request, finished: () -> Unit) {
            val previous = job
            job?.cancel()
            val launched = scope.launch {
                try {
                    withContext(NonCancellable) { previous?.join() }
                    ensureActive()
                    request.block()
                } catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) {  request.onError("曲谱播放中断：${error.message ?: error.javaClass.simpleName}"); request.onStop() }
                finally { finished() }
            }
            job = launched
            launched.invokeOnCompletion { if (job === launched) job = null }
        }
        fun play(context: Context, title: String, remote: Boolean, onStop: () -> Unit, onError: (String) -> Unit = {}, block: suspend () -> Unit) {

            val request = Request(title, remote, onStop, onError, block)
            pending = request
            if (remote) {
                try { context.applicationContext.startForegroundService(Intent(context, ScorePlaybackService::class.java)) }
                catch (error: Exception) { pending = null; onError("无法启动后台播放：${error.message ?: error.javaClass.simpleName}"); onStop() }
            } else launchRequest(request) { if (pending === request) pending = null }
        }
        suspend fun pauseAndJoin(context: Context) {
            val stopped = job
            pause(context)
            stopped?.join()
        }
        fun pause(context: Context) {

            val request = pending; pending = null
            request?.onStop(); job?.cancel()
            val stopped = job
            scope.launch {
                stopped?.join()
                if (pending == null) context.applicationContext.stopService(Intent(context, ScorePlaybackService::class.java))
            }
        }
    }
}
