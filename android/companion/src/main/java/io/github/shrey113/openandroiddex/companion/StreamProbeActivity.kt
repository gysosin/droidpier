package io.github.shrey113.openandroiddex.companion

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.core.content.ContextCompat
import kotlin.math.abs

class StreamProbeActivity : Activity() {
    private val modeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            showMode(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        showMode(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        showMode(intent)
    }

    override fun onStart() {
        super.onStart()
        ContextCompat.registerReceiver(
            this,
            modeReceiver,
            IntentFilter(ACTION_SET_MODE),
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    override fun onStop() {
        unregisterReceiver(modeReceiver)
        super.onStop()
    }

    private fun showMode(intent: Intent) {
        val mode = StreamProbeMode.parse(intent.getStringExtra(EXTRA_MODE))
        setContentView(StreamProbeView(mode))
        reportDisplay(intent.getStringExtra(EXTRA_REPORT_ID))
    }

    private fun reportDisplay(reportId: String?) {
        if (reportId.isNullOrBlank()) return
        window.decorView.post {
            val currentDisplay = window.decorView.display
            val displayId = currentDisplay?.displayId ?: -1
            val refreshHz = currentDisplay?.refreshRate ?: 0f
            Log.i(
                LOG_TAG,
                "report_id=$reportId display_id=$displayId refresh_hz=$refreshHz",
            )
        }
    }

    private inner class StreamProbeView(
        private val mode: StreamProbeMode,
    ) : View(this@StreamProbeActivity), Choreographer.FrameCallback {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var lightBackground = false
        private var frameNumber = 0L
        private var firstFrameTimeNanos = 0L
        private var callbackPosted = false
        private val primeLatencyFrame = Runnable {
            if (isAttachedToWindow && mode == StreamProbeMode.LATENCY) {
                lightBackground = true
                invalidate()
            }
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (mode == StreamProbeMode.MOTION) {
                postNextFrame()
            } else {
                postDelayed(primeLatencyFrame, LATENCY_PRIME_DELAY_MS)
            }
        }

        override fun onDetachedFromWindow() {
            callbackPosted = false
            removeCallbacks(primeLatencyFrame)
            Choreographer.getInstance().removeFrameCallback(this)
            super.onDetachedFromWindow()
        }

        override fun doFrame(frameTimeNanos: Long) {
            callbackPosted = false
            if (!isAttachedToWindow || mode != StreamProbeMode.MOTION) return
            if (firstFrameTimeNanos == 0L) firstFrameTimeNanos = frameTimeNanos
            frameNumber += 1
            invalidate()
            postNextFrame()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (mode == StreamProbeMode.LATENCY) {
                drawLatencyProbe(canvas)
            } else {
                drawMotionProbe(canvas)
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (mode == StreamProbeMode.LATENCY && event.actionMasked == MotionEvent.ACTION_DOWN) {
                lightBackground = !lightBackground
                invalidate()
            }
            return true
        }

        private fun drawLatencyProbe(canvas: Canvas) {
            val background = if (lightBackground) Color.WHITE else Color.BLACK
            val inverse = if (lightBackground) Color.BLACK else Color.WHITE
            canvas.drawColor(background)
            paint.color = inverse
            canvas.drawRect(0f, 0f, width.toFloat(), PROBE_BAR_HEIGHT_PX, paint)
        }

        private fun drawMotionProbe(canvas: Canvas) {
            canvas.drawColor(Color.BLACK)
            val elapsedSeconds = if (firstFrameTimeNanos == 0L) {
                0f
            } else {
                (System.nanoTime() - firstFrameTimeNanos) / 1_000_000_000f
            }
            val maxX = (width - BOX_SIZE_PX).coerceAtLeast(1f)
            val maxY = (height - BOX_SIZE_PX).coerceAtLeast(1f)
            val x = reflectedPosition(elapsedSeconds * 540f, maxX)
            val y = reflectedPosition(elapsedSeconds * 360f, maxY)

            paint.color = Color.rgb(124, 77, 255)
            canvas.drawRect(x, y, x + BOX_SIZE_PX, y + BOX_SIZE_PX, paint)
            paint.color = Color.WHITE
            paint.textSize = 48f
            canvas.drawText(frameNumber.toString(), 32f, height - 40f, paint)
        }

        private fun reflectedPosition(distance: Float, limit: Float): Float {
            val period = limit * 2f
            val phase = distance % period
            return limit - abs(limit - phase)
        }

        private fun postNextFrame() {
            if (callbackPosted) return
            callbackPosted = true
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private companion object {
        const val EXTRA_MODE = "mode"
        const val EXTRA_REPORT_ID = "report_id"
        const val LOG_TAG = "OpenDexStreamProbe"
        const val ACTION_SET_MODE =
            "io.github.shrey113.openandroiddex.companion.SET_STREAM_PROBE_MODE"
        const val BOX_SIZE_PX = 200f
        const val PROBE_BAR_HEIGHT_PX = 24f
        const val LATENCY_PRIME_DELAY_MS = 250L
    }
}
