package com.lkgrouptrading.app;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewTreeObserver;

/** Debug-only fixture: hold the production OS splash for a real emulator capture. */
public final class StartupPreviewActivity extends Activity {
    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        View view = new View(this);
        setContentView(view);
        ViewTreeObserver.OnPreDrawListener hold = () -> false;
        view.getViewTreeObserver().addOnPreDrawListener(hold);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            view.getViewTreeObserver().removeOnPreDrawListener(hold);
            finish();
        }, 4000);
    }
}
