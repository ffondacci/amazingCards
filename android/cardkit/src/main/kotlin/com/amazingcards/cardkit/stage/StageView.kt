// The stage as a composable: a SurfaceView the native renderer draws into,
// with the drag and tap gestures wired to the scene.
package com.amazingcards.cardkit.stage

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView

/** Hosts the native stage. Create the [Stage] with `rememberStage`. */
@SuppressLint("ClickableViewAccessibility")
@Composable
fun StageView(stage: Stage, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val view = remember(stage) {
        SurfaceView(context).apply {
            holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) { stage.setSurface(holder.surface) }
                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { stage.resize(width, height) }
                override fun surfaceDestroyed(holder: SurfaceHolder) { stage.setSurface(null) }
            })
            setOnTouchListener { _, event ->
                val t = event.eventTime / 1000.0
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> stage.dragBegan(event.x, event.y, t)
                    MotionEvent.ACTION_MOVE -> stage.dragChanged(event.x, event.y, t)
                    MotionEvent.ACTION_UP -> stage.dragEnded(event.x, event.y, t)
                    MotionEvent.ACTION_CANCEL -> stage.dragEnded(event.x, event.y, t)
                }
                true
            }
        }
    }
    DisposableEffect(stage) { onDispose { stage.setSurface(null) } }
    // Device tilt like DeviceMotionSource on iOS: attitude relative to the
    // pose at start, 0.35 rad = full tilt, low-pass filtered, clamped to −1…1.
    DisposableEffect(stage) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR) ?: manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        val listener = object : SensorEventListener {
            private val rotation = FloatArray(9)
            private val orientation = FloatArray(3)
            private var reference: FloatArray? = null
            private var x = 0f
            private var y = 0f
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                SensorManager.getOrientation(rotation, orientation)
                val ref = reference ?: orientation.clone().also { reference = it }
                val roll = orientation[2] - ref[2]
                val pitch = orientation[1] - ref[1]
                val wantedX = (roll / 0.35f).coerceIn(-1f, 1f)
                val wantedY = (-pitch / 0.35f).coerceIn(-1f, 1f)
                x = x * 0.75f + wantedX * 0.25f
                y = y * 0.75f + wantedY * 0.25f
                stage.tilt(x, y)
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        if (sensor != null) manager?.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { manager?.unregisterListener(listener) }
    }
    AndroidView(factory = { view }, modifier = modifier.fillMaxSize())
}
