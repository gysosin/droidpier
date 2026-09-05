package io.github.shrey113.openandroiddex.agent;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.AdaptiveIconDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.Looper;
import android.util.Base64;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.lang.reflect.Method;

/** Resolves launcher labels and bounded icons from Android's package manager. */
final class ApplicationMetadataReader {
    private static final int ICON_SIZE_PX = 64;

    private final PackageManager packageManager;

    private ApplicationMetadataReader(PackageManager packageManager) {
        this.packageManager = packageManager;
    }

    static ApplicationMetadataReader create() throws Exception {
        // The agent is launched by app_process rather than as an APK, so it has
        // no application Context. ActivityThread's system context is the same
        // process-local bridge used by Android shell tools for framework APIs.
        if (Looper.myLooper() == null) Looper.prepareMainLooper();
        Class<?> activityThreadClass = Class.forName("android.app.ActivityThread");
        Method systemMain = activityThreadClass.getDeclaredMethod("systemMain");
        Object activityThread = systemMain.invoke(null);
        Method getSystemContext = activityThreadClass.getDeclaredMethod("getSystemContext");
        Context context = (Context) getSystemContext.invoke(activityThread);
        if (context == null || context.getPackageManager() == null) {
            throw new IllegalStateException("Android package manager is unavailable");
        }
        return new ApplicationMetadataReader(context.getPackageManager());
    }

    JSONObject describe(String packageName) throws Exception {
        JSONObject result = new JSONObject()
            .put("packageName", packageName)
            .put("label", packageName);
        try {
            ApplicationInfo info = packageManager.getApplicationInfo(packageName, 0);
            CharSequence label = packageManager.getApplicationLabel(info);
            if (label != null && !label.toString().trim().isEmpty()) {
                result.put("label", label.toString().trim());
            }
            result.put(
                "isSystemApp",
                (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0
            );
            String icon = encodeIcon(packageManager.getApplicationIcon(info));
            if (icon != null) result.put("iconPngBase64", icon);
        } catch (Exception ignored) {
            // One malformed/unavailable package must not discard the catalog.
        }
        return result;
    }

    private static String encodeIcon(Drawable drawable) {
        if (drawable == null) return null;
        Bitmap bitmap = Bitmap.createBitmap(
            ICON_SIZE_PX,
            ICON_SIZE_PX,
            Bitmap.Config.ARGB_8888
        );
        Canvas canvas = new Canvas(bitmap);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && drawable instanceof AdaptiveIconDrawable) {
            // Drawn layer by layer under the desk's own rounded-square mask.
            // drawable.draw() applies the launcher's mask — a circle on some
            // phones — and the desk then showed discs where its design, and
            // the reference it follows, draw tiles. The desk decides the
            // shape of its icons; the phone supplies the artwork.
            AdaptiveIconDrawable adaptive = (AdaptiveIconDrawable) drawable;
            float radius = ICON_SIZE_PX * 14f / 48f;
            Path mask = new Path();
            mask.addRoundRect(
                new RectF(0, 0, ICON_SIZE_PX, ICON_SIZE_PX),
                radius,
                radius,
                Path.Direction.CW
            );
            canvas.clipPath(mask);
            // Adaptive layers are authored on a 108dp canvas whose visible
            // area is the inner 72dp, so each layer bleeds a quarter past
            // every edge of the icon.
            int bleed = ICON_SIZE_PX / 4;
            Rect bounds = new Rect(
                -bleed,
                -bleed,
                ICON_SIZE_PX + bleed,
                ICON_SIZE_PX + bleed
            );
            Drawable background = adaptive.getBackground();
            if (background != null) {
                background.setBounds(bounds);
                background.draw(canvas);
            }
            Drawable foreground = adaptive.getForeground();
            if (foreground != null) {
                foreground.setBounds(bounds);
                foreground.draw(canvas);
            }
        } else {
            drawable.setBounds(0, 0, ICON_SIZE_PX, ICON_SIZE_PX);
            drawable.draw(canvas);
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try {
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)) return null;
            return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP);
        } finally {
            bitmap.recycle();
        }
    }
}
