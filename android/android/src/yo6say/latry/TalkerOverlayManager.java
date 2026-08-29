package yo6say.latry;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Small Mumble-style floating talker card shown above other Android apps.
 *
 * This class deliberately owns only the native overlay window. The source of
 * the talker state stays in Latry's existing reflector/background-service
 * pipeline so we do not need a second connection or polling endpoint.
 */
public final class TalkerOverlayManager {
    private static final String TAG = "TalkerOverlay";

    private final Context context;
    private final WindowManager windowManager;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private View overlayView;
    private TextView talkerView;
    private TextView detailView;
    private WindowManager.LayoutParams layoutParams;
    private boolean permissionWarningLogged;

    public TalkerOverlayManager(Context context) {
        this.context = context.getApplicationContext();
        this.windowManager = (WindowManager) this.context.getSystemService(Context.WINDOW_SERVICE);
    }

    public boolean hasOverlayPermission() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context);
    }

    public void openOverlayPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || hasOverlayPermission()) {
            return;
        }

        Intent intent = new Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + context.getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(intent);
    }

    public void showTalker(String talker, int talkGroup) {
        final String normalizedTalker = talker == null ? "" : talker.trim();
        if (normalizedTalker.isEmpty()) {
            hide();
            return;
        }

        mainHandler.post(() -> showTalkerOnMainThread(normalizedTalker, talkGroup));
    }

    public void hide() {
        mainHandler.post(this::hideOnMainThread);
    }

    public void destroy() {
        hide();
    }

    private void showTalkerOnMainThread(String talker, int talkGroup) {
        if (!hasOverlayPermission()) {
            if (!permissionWarningLogged) {
                Log.w(TAG, "Talker overlay permission is not granted");
                permissionWarningLogged = true;
            }
            return;
        }

        permissionWarningLogged = false;
        ensureOverlayView();

        talkerView.setText(talker);
        detailView.setText(talkGroup > 0 ? "TG " + talkGroup + "  •  Latry" : "Latry");

        if (overlayView.getParent() == null && windowManager != null) {
            try {
                windowManager.addView(overlayView, layoutParams);
                Log.d(TAG, "Talker overlay shown: " + talker);
            } catch (RuntimeException e) {
                Log.e(TAG, "Unable to add talker overlay", e);
            }
        }
    }

    private void hideOnMainThread() {
        if (overlayView == null || overlayView.getParent() == null || windowManager == null) {
            return;
        }

        try {
            windowManager.removeView(overlayView);
            Log.d(TAG, "Talker overlay hidden");
        } catch (RuntimeException e) {
            Log.w(TAG, "Unable to remove talker overlay cleanly", e);
        }
    }

    private void ensureOverlayView() {
        if (overlayView != null) {
            return;
        }

        LinearLayout card = new LinearLayout(context);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(10), dp(16), dp(10));
        card.setMinimumWidth(dp(210));
        card.setElevation(dp(8));

        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.argb(235, 24, 24, 27));
        background.setCornerRadius(dp(14));
        background.setStroke(dp(1), Color.argb(180, 90, 90, 96));
        card.setBackground(background);

        TextView labelView = new TextView(context);
        labelView.setText("●  TALKER");
        labelView.setTextColor(Color.rgb(76, 217, 100));
        labelView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        labelView.setAllCaps(true);

        talkerView = new TextView(context);
        talkerView.setTextColor(Color.WHITE);
        talkerView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        talkerView.setPadding(0, dp(2), 0, 0);
        talkerView.setSingleLine(true);

        detailView = new TextView(context);
        detailView.setTextColor(Color.argb(220, 205, 205, 210));
        detailView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        detailView.setPadding(0, dp(2), 0, 0);

        card.addView(labelView);
        card.addView(talkerView);
        card.addView(detailView);

        int overlayType = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;

        layoutParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        layoutParams.gravity = Gravity.TOP | Gravity.START;
        layoutParams.x = dp(20);
        layoutParams.y = dp(90);

        installDragHandler(card);
        overlayView = card;
    }

    private void installDragHandler(View view) {
        view.setOnTouchListener(new View.OnTouchListener() {
            private int startX;
            private int startY;
            private float downX;
            private float downY;

            @Override
            public boolean onTouch(View touchedView, MotionEvent event) {
                if (layoutParams == null || windowManager == null) {
                    return false;
                }

                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        startX = layoutParams.x;
                        startY = layoutParams.y;
                        downX = event.getRawX();
                        downY = event.getRawY();
                        return true;

                    case MotionEvent.ACTION_MOVE:
                        layoutParams.x = startX + Math.round(event.getRawX() - downX);
                        layoutParams.y = startY + Math.round(event.getRawY() - downY);
                        if (overlayView != null && overlayView.getParent() != null) {
                            windowManager.updateViewLayout(overlayView, layoutParams);
                        }
                        return true;

                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        return true;

                    default:
                        return false;
                }
            }
        });
    }

    private int dp(int value) {
        float density = context.getResources().getDisplayMetrics().density;
        return Math.round(value * density);
    }
}
