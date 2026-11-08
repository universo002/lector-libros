package com.lector.lector_tts;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Motor de voz de Lector para Android: usa el TextToSpeech del sistema (Google)
 * con una cola de frases y silencios para las pausas.
 */
public class LectorTtsPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;
    private TextToSpeech tts;
    private boolean ready = false;
    private boolean initDone = false;
    private final List<Runnable> pending = new ArrayList<>();
    private final Handler main = new Handler(Looper.getMainLooper());
    private BroadcastReceiver noisyReceiver;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "lector_tts");
        channel.setMethodCallHandler(this);
        initTts();
        registerNoisy();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
        if (noisyReceiver != null) {
            try {
                context.unregisterReceiver(noisyReceiver);
            } catch (Exception ignored) {
            }
        }
    }

    private void initTts() {
        tts = new TextToSpeech(context, status -> main.post(() -> {
            ready = status == TextToSpeech.SUCCESS;
            initDone = true;
            if (ready) {
                tts.setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build());
                tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                    @Override
                    public void onStart(String utteranceId) {
                        send("onStart", utteranceId, null);
                    }

                    @Override
                    public void onDone(String utteranceId) {
                        send("onFinish", utteranceId, null);
                    }

                    @Override
                    public void onError(String utteranceId) {
                        send("onFinish", utteranceId, null);
                    }

                    @Override
                    public void onRangeStart(String utteranceId, int start, int end, int frame) {
                        Map<String, Object> extra = new HashMap<>();
                        extra.put("loc", start);
                        extra.put("len", end - start);
                        send("onRange", utteranceId, extra);
                    }
                });
            }
            for (Runnable r : pending) r.run();
            pending.clear();
        }));
    }

    private void whenReady(Runnable r) {
        if (initDone || tts == null) {
            r.run();
        } else {
            pending.add(r);
        }
    }

    private void registerNoisy() {
        noisyReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent intent) {
                if (AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(intent.getAction())) {
                    if (tts != null) tts.stop();
                    main.post(() -> channel.invokeMethod("onRouteLost", null));
                }
            }
        };
        IntentFilter filter = new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                context.registerReceiver(noisyReceiver, filter);
            }
        } catch (Exception ignored) {
        }
    }

    private void send(String method, String utteranceId, Map<String, Object> extra) {
        if (utteranceId == null || utteranceId.startsWith("s")) return; // silencios
        final int id;
        try {
            id = Integer.parseInt(utteranceId);
        } catch (NumberFormatException e) {
            return;
        }
        final Map<String, Object> args = new HashMap<>();
        args.put("id", id);
        if (extra != null) args.putAll(extra);
        main.post(() -> channel.invokeMethod(method, args));
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "getVoices":
                whenReady(() -> result.success(voices()));
                break;
            case "enqueue": {
                final List<Map<String, Object>> items = call.argument("items");
                whenReady(() -> {
                    if (items != null && ready) {
                        for (Map<String, Object> it : items) enqueue(it);
                    }
                    result.success(ready);
                });
                break;
            }
            case "stop":
                if (tts != null) tts.stop();
                result.success(true);
                break;
            case "pause":
                // Android no puede pausar en medio de una frase: se detiene y luego se retoma desde la frase actual.
                if (tts != null) tts.stop();
                result.success(true);
                break;
            case "resume":
                result.success(false);
                break;
            case "isSpeaking":
                result.success(tts != null && tts.isSpeaking());
                break;
            default:
                result.notImplemented();
        }
    }

    private static double num(Map<String, Object> m, String k, double def) {
        Object o = m.get(k);
        return o instanceof Number ? ((Number) o).doubleValue() : def;
    }

    private void enqueue(Map<String, Object> it) {
        Object textObj = it.get("text");
        Object idObj = it.get("id");
        if (!(textObj instanceof String) || !(idObj instanceof Number)) return;
        String text = (String) textObj;
        String id = String.valueOf(((Number) idObj).intValue());

        Object voiceObj = it.get("voice");
        boolean voiceSet = false;
        if (voiceObj instanceof String && !((String) voiceObj).isEmpty()) {
            Set<Voice> all = tts.getVoices();
            if (all != null) {
                for (Voice v : all) {
                    if (v.getName().equals(voiceObj)) {
                        tts.setVoice(v);
                        voiceSet = true;
                        break;
                    }
                }
            }
        }
        if (!voiceSet) {
            Object lang = it.get("lang");
            if (lang instanceof String) tts.setLanguage(Locale.forLanguageTag((String) lang));
        }

        // La app usa la escala de iPhone (0,5 = normal). En Android 1,0 = normal.
        double rate = num(it, "rate", 0.46) / 0.5;
        tts.setSpeechRate((float) Math.max(0.3, Math.min(2.5, rate)));
        tts.setPitch((float) num(it, "pitch", 1.0));

        Bundle params = new Bundle();
        params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, (float) num(it, "volume", 1.0));

        long pre = Math.round(num(it, "pre", 0) * 1000);
        long post = Math.round(num(it, "post", 0) * 1000);
        if (pre > 0) tts.playSilentUtterance(pre, TextToSpeech.QUEUE_ADD, "s" + id + "a");
        tts.speak(text, TextToSpeech.QUEUE_ADD, params, id);
        if (post > 0) tts.playSilentUtterance(post, TextToSpeech.QUEUE_ADD, "s" + id + "b");
    }

    private List<Map<String, Object>> voices() {
        List<Map<String, Object>> out = new ArrayList<>();
        if (tts == null) return out;
        Set<Voice> all;
        try {
            all = tts.getVoices();
        } catch (Exception e) {
            return out;
        }
        if (all == null) return out;
        for (Voice v : all) {
            if (v.isNetworkConnectionRequired()) continue; // solo voces que funcionan sin internet
            Set<String> feats = v.getFeatures();
            if (feats != null && feats.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)) continue;
            String name = v.getName();
            String lower = name.toLowerCase(Locale.ROOT);
            int gender = lower.contains("#female") ? 2 : (lower.contains("#male") ? 1 : 0);
            int q = v.getQuality();
            int quality = q >= Voice.QUALITY_VERY_HIGH ? 3 : (q >= Voice.QUALITY_HIGH ? 2 : 1);
            Map<String, Object> m = new HashMap<>();
            m.put("id", name);
            m.put("name", name);
            m.put("lang", v.getLocale().toLanguageTag());
            m.put("quality", quality);
            m.put("gender", gender);
            out.add(m);
        }
        return out;
    }
}
