// Interactive container: drag to tilt, gyroscope, perspective rotation,
// dynamic shadow, a showcase circle on appear, and the motion the shader
// passes read. A port of CardMotionStage / DeviceMotionSource / TiltTransform.
package com.amazingcards.cardkit.fx

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Gyroscope tilt relative to the pose at start, 0.35 rad = full tilt, low-pass filtered (DeviceMotionSource). */
@Composable
fun rememberDeviceTilt(enabled: Boolean): State<Pair<Float, Float>> {
    val context = LocalContext.current
    val tilt = remember { mutableStateOf(0f to 0f) }
    DisposableEffect(enabled) {
        if (!enabled) { tilt.value = 0f to 0f; return@DisposableEffect onDispose {} }
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
                val wantedX = ((orientation[2] - ref[2]) / 0.35f).coerceIn(-1f, 1f)
                val wantedY = (-(orientation[1] - ref[1]) / 0.35f).coerceIn(-1f, 1f)
                x = x * 0.75f + wantedX * 0.25f
                y = y * 0.75f + wantedY * 0.25f
                tilt.value = x to y
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        if (sensor != null) manager?.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { manager?.unregisterListener(listener); tilt.value = 0f to 0f }
    }
    return tilt
}

/** Seconds since the stage appeared, ticking with the display while `animates`. */
@Composable
fun rememberMotionClock(animates: Boolean): State<Float> {
    val time = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(animates) {
        if (!animates) return@LaunchedEffect
        val start = System.nanoTime()
        while (true) { withFrameNanos { now -> time.floatValue = (now - start) / 1e9f } }
    }
    return time
}

/**
 * Drag anywhere on the card: the finger becomes the pointer and the card
 * tilts toward it, springing back on release. `showcase` tilts it in a slow
 * circle for 3.5 s on appear. The content gets the current [CardMotion].
 */
@Composable
fun CardMotionStage(
    modifier: Modifier = Modifier,
    usesDeviceMotion: Boolean = true,
    animates: Boolean = true,
    maxRotation: Float = 14f,
    showcase: Boolean = false,
    interactive: Boolean = true,
    content: @Composable (CardMotion) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val tiltX = remember { Animatable(0f) }
    val tiltY = remember { Animatable(0f) }
    var pointer by remember { mutableStateOf<Pair<Float, Float>?>(null) }
    var isInteracting by remember { mutableStateOf(false) }
    var size by remember { mutableStateOf(IntSize.Zero) }
    val device by rememberDeviceTilt(usesDeviceMotion)
    val time by rememberMotionClock(animates)
    val tx = (tiltX.value + device.first).coerceIn(-1f, 1f)
    val ty = (tiltY.value + device.second).coerceIn(-1f, 1f)
    val motion = CardMotion(tx, ty, pointer, time, isInteracting)

    LaunchedEffect(showcase) {
        if (!showcase) return@LaunchedEffect
        delay(350)
        val start = System.nanoTime()
        while (!isInteracting) {
            val elapsed = (System.nanoTime() - start) / 1e9f
            if (elapsed >= 3.5f) break
            val envelope = min(1f, elapsed / 0.6f) * min(1f, (3.5f - elapsed) / 0.8f)
            val angle = elapsed * 1.9f
            tiltX.snapTo(sin(angle) * 0.75f * envelope)
            tiltY.snapTo(cos(angle) * 0.55f * envelope)
            pointer = (0.5f + sin(angle) * 0.4f * envelope) to (0.5f + cos(angle) * 0.4f * envelope)
            withFrameNanos { }
        }
        if (!isInteracting) {
            pointer = null
            launch { tiltX.animateTo(0f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow)) }
            launch { tiltY.animateTo(0f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow)) }
        }
    }

    val shadowScale = max(min(size.width, size.height) * 0.05f, 4f)
    Box(
        modifier
            .onSizeChanged { size = it }
            .graphicsLayer {
                rotationX = -ty * maxRotation
                rotationY = tx * maxRotation
                cameraDistance = 2.6f * max(size.width, size.height) / density
                transformOrigin = TransformOrigin.Center
                scaleX = if (isInteracting) 1.03f else 1f
                scaleY = scaleX
                shadowElevation = shadowScale * (if (isInteracting) 1.6f else 1.1f)
                ambientShadowColor = Color.Black
                spotShadowColor = Color.Black
            }
            .pointerInput(interactive) {
                if (!interactive) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    down.consume()
                    fun apply(position: Offset) {
                        if (size.width == 0 || size.height == 0) return
                        val px = (position.x / size.width).coerceIn(0f, 1f)
                        val py = (position.y / size.height).coerceIn(0f, 1f)
                        pointer = px to py
                        isInteracting = true
                        scope.launch { tiltX.animateTo((px - 0.5f) * 2, spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMedium)) }
                        scope.launch { tiltY.animateTo((py - 0.5f) * 2, spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMedium)) }
                    }
                    apply(down.position)
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        change.consume()
                        apply(change.position)
                    }
                    pointer = null
                    isInteracting = false
                    scope.launch { tiltX.animateTo(0f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessLow)) }
                    scope.launch { tiltY.animateTo(0f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessLow)) }
                }
            },
    ) {
        content(motion)
    }
}
