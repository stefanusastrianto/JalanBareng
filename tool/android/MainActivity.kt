package id.jalanbareng.jalan_bareng

import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.text.Spannable
import android.text.SpannableString
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/**
 * Kompres video dan rakit video recap memakai Media3 Transformer (komponen video resmi Android).
 * Dipanggil dari Dart lewat channel "jalanbareng/video".
 */
@OptIn(UnstableApi::class)
class MainActivity : FlutterActivity() {
    private var transformer: Transformer? = null
    private val progressHolder = ProgressHolder()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jalanbareng/video").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "compress" -> compress(call, result)
                    "recap" -> recap(call, result)
                    "progress" -> {
                        val t = transformer
                        if (t == null) {
                            result.success(-1)
                        } else {
                            val state = t.getProgress(progressHolder)
                            result.success(if (state == Transformer.PROGRESS_STATE_AVAILABLE) progressHolder.progress else -1)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                transformer = null
                result.error("video", e.message ?: e.toString(), null)
            }
        }
    }

    private fun build(bitrate: Int, done: (String?) -> Unit): Transformer {
        val encoder = DefaultEncoderFactory.Builder(applicationContext)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
            .build()
        return Transformer.Builder(applicationContext)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoder)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    done(null)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    done(exportException.message ?: "Ekspor video gagal")
                }
            })
            .build()
    }

    private fun compress(call: MethodCall, result: MethodChannel.Result) {
        val input = call.argument<String>("input")!!
        val output = call.argument<String>("output")!!
        val w = call.argument<Int>("width") ?: 1280
        val h = call.argument<Int>("height") ?: 720
        File(output).delete()
        val effects = Effects(ImmutableList.of(), ImmutableList.of<Effect>(Presentation.createForWidthAndHeight(w, h, Presentation.LAYOUT_SCALE_TO_FIT)))
        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(input)))).setEffects(effects).build()
        val t = build(2_500_000) { err ->
            transformer = null
            if (err == null) result.success(output) else result.error("video", err, null)
        }
        transformer = t
        t.start(item, output)
    }

    private fun text(value: String, size: Int, x: Float, y: Float, bold: Boolean): TextOverlay {
        val s = SpannableString(value)
        val n = s.length
        s.setSpan(ForegroundColorSpan(Color.WHITE), 0, n, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        s.setSpan(BackgroundColorSpan(Color.argb(150, 0, 0, 0)), 0, n, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        s.setSpan(AbsoluteSizeSpan(size), 0, n, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (bold) s.setSpan(StyleSpan(Typeface.BOLD), 0, n, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        val settings = OverlaySettings.Builder().setBackgroundFrameAnchor(x, y).build()
        return TextOverlay.createStaticTextOverlay(s, settings)
    }

    private fun recap(call: MethodCall, result: MethodChannel.Result) {
        val spec = JSONObject(call.argument<String>("spec")!!)
        val output = spec.getString("output")
        val w = spec.optInt("width", 720)
        val h = spec.optInt("height", 1280)
        val music = spec.optString("music", "")
        val withAudio = spec.optBoolean("audio", true)
        val arr = spec.getJSONArray("items")
        val big = if (w < h) 46 else 56
        val small = if (w < h) 34 else 38
        val list = ArrayList<EditedMediaItem>()
        for (k in 0 until arr.length()) {
            val o = arr.getJSONObject(k)
            val file = Uri.fromFile(File(o.getString("path")))
            val isPhoto = o.optString("type") == "photo"
            val videoEffects = ArrayList<Effect>()
            videoEffects.add(Presentation.createForWidthAndHeight(w, h, Presentation.LAYOUT_SCALE_TO_FIT))
            val overlays = ArrayList<TextureOverlay>()
            val title = o.optString("title", "")
            val caption = o.optString("caption", "")
            if (title.isNotEmpty()) overlays.add(text(title, big, 0f, 0.6f, true))
            if (caption.isNotEmpty()) overlays.add(text(caption, small, 0f, -0.78f, false))
            if (overlays.isNotEmpty()) videoEffects.add(OverlayEffect(ImmutableList.copyOf(overlays)))
            val effects = Effects(ImmutableList.of(), ImmutableList.copyOf(videoEffects))
            val edited = if (isPhoto) {
                val mi = MediaItem.Builder().setUri(file).setMimeType(MimeTypes.IMAGE_JPEG).build()
                EditedMediaItem.Builder(mi)
                    .setDurationUs(o.optLong("durationMs", 2500) * 1000)
                    .setFrameRate(30)
                    .setEffects(effects)
                    .build()
            } else {
                val clip = MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(o.optLong("startMs", 0))
                    .setEndPositionMs(o.optLong("endMs", 4000))
                    .build()
                val mi = MediaItem.Builder().setUri(file).setClippingConfiguration(clip).build()
                EditedMediaItem.Builder(mi)
                    .setRemoveAudio(!withAudio || music.isNotEmpty())
                    .setEffects(effects)
                    .build()
            }
            list.add(edited)
        }
        val sequences = ArrayList<EditedMediaItemSequence>()
        sequences.add(EditedMediaItemSequence(list))
        if (music.isNotEmpty()) {
            val m = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(music)))).build()
            sequences.add(EditedMediaItemSequence(ImmutableList.of(m), true))
        }
        val builder = Composition.Builder(sequences)
        if (music.isEmpty() && withAudio) builder.experimentalSetForceAudioTrack(true)
        val composition = builder.build()
        File(output).delete()
        val t = build(4_000_000) { err ->
            transformer = null
            if (err == null) result.success(output) else result.error("video", err, null)
        }
        transformer = t
        t.start(composition, output)
    }
}
