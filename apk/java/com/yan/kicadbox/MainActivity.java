package com.yan.kicadbox;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.Icon;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** One-tap installer + launcher for the Termux/proot KiCad setup (see install.sh in assets). */
public class MainActivity extends Activity {
    static final String ACTION_LAUNCH = "com.yan.kicadbox.LAUNCH";
    static final String ACTION_STOP = "com.yan.kicadbox.STOP";
    static final String TERMUX = "com.termux";
    static final String X11 = "com.termux.x11";
    static final String WIDGET = "com.termux.widget";
    static final String PERM_RUN = "com.termux.permission.RUN_COMMAND";
    static final String PREFIX = "/data/data/com.termux/files/usr";
    static final String HOME = "/data/data/com.termux/files/home";
    static final String ENABLE_CMD =
        "mkdir -p ~/.termux && grep -q '^allow-external-apps' ~/.termux/termux.properties 2>/dev/null "
        + "|| echo 'allow-external-apps=true' >> ~/.termux/termux.properties; termux-reload-settings";

    static final int BG = Color.parseColor("#0E1A17");
    static final int CARD = Color.parseColor("#16302A");
    static final int ACCENT = Color.parseColor("#2EC4A0");
    static final int TEXT = Color.parseColor("#E8F7F2");
    static final int MUTED = Color.parseColor("#8FB5AA");
    static final int BAD = Color.parseColor("#E5675B");

    private final Handler ui = new Handler(Looper.getMainLooper());
    private SharedPreferences prefs;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("opts", MODE_PRIVATE);
        if (handleAction(getIntent())) return;
        render();
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        if (!handleAction(i)) render();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (getIntent() == null || (!ACTION_LAUNCH.equals(getIntent().getAction())
                && !ACTION_STOP.equals(getIntent().getAction()))) render();
    }

    /** Shortcut intents act without showing the UI. */
    private boolean handleAction(Intent i) {
        String a = i == null ? null : i.getAction();
        if (ACTION_LAUNCH.equals(a)) {
            setContentView(message("Starting KiCad..."));
            launchKicad();
            ui.postDelayed(this::finish, 3500);
            return true;
        }
        if (ACTION_STOP.equals(a)) {
            stopKicad();
            finish();
            return true;
        }
        return false;
    }

    // ---- Termux plumbing -------------------------------------------------------------------

    private boolean installed(String pkg) {
        try { getPackageManager().getPackageInfo(pkg, 0); return true; }
        catch (PackageManager.NameNotFoundException e) { return false; }
    }

    private boolean permitted() {
        return checkSelfPermission(PERM_RUN) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean runInTermux(String path, String[] args, boolean background, String sessionAction) {
        Intent i = new Intent("com.termux.RUN_COMMAND");
        i.setClassName(TERMUX, "com.termux.app.RunCommandService");
        i.putExtra("com.termux.RUN_COMMAND_PATH", path);
        i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args);
        i.putExtra("com.termux.RUN_COMMAND_WORKDIR", HOME);
        i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", background);
        i.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", sessionAction);
        try {
            try { startService(i); } catch (IllegalStateException e) { startForegroundService(i); }
            return true;
        } catch (SecurityException e) {
            toast("Permission denied. Tap Grant permission (step 1); if it is already granted, run termux-reload-settings in Termux or restart it.");
            return false;
        } catch (Exception e) {
            toast("Could not reach Termux: " + e.getClass().getSimpleName() + " " + e.getMessage());
            return false;
        }
    }

    /** Runs a Termux script through a login bash, passing the path explicitly so its shebang line is never used. */
    private boolean runTermuxCmd(String cmd, boolean background, String sessionAction) {
        return runInTermux(PREFIX + "/bin/bash", new String[]{"-lc", "exec bash \"" + PREFIX + "/bin/" + cmd + "\""}, background, sessionAction);
    }

    private void launchKicad() {
        if (!installed(TERMUX) || !installed(X11)) { toast("Install Termux and Termux:X11 first."); return; }
        boolean visible = prefs.getBoolean("visible", true);
        // Visible: a real Termux session opens first, so any error from kicad-start is readable.
        if (!runTermuxCmd("kicad-start", !visible, visible ? "0" : "2")) return;
        // The X11 viewer app must be in front; it attaches once the server inside Termux is up.
        ui.postDelayed(() -> {
            Intent x = new Intent().setComponent(new ComponentName(X11, "com.termux.x11.MainActivity"));
            x.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { startActivity(x); } catch (Exception e) { toast("Open Termux:X11 manually."); }
        }, prefs.getBoolean("visible", true) ? 4000 : 2500);
    }

    private void stopKicad() {
        if (runTermuxCmd("kicad-stop", true, "2")) toast("Stopping KiCad");
    }

    private void installKicad() {
        String script;
        try { script = readAsset("install.sh"); } catch (Exception e) { toast("Bundled installer missing"); return; }
        StringBuilder pre = new StringBuilder();
        if (prefs.getBoolean("3d", false)) pre.append("export KICAD_3D=1\n");
        if (prefs.getBoolean("virgl", false)) pre.append("export KICAD_GPU=virgl\n");
        if (prefs.getBoolean("hidpi", false)) pre.append("export KICAD_SCALE=2\n");
        String full = pre + script + "\nprintf '\\nPress Enter to close...'; read -r _\n";
        // action 0: open Termux and show the new session so progress and permission prompts are visible.
        runInTermux(PREFIX + "/bin/bash", new String[]{"-c", full}, false, "0");
    }

    private String readAsset(String name) throws Exception {
        try (InputStream in = getAssets().open(name)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toString(StandardCharsets.UTF_8.name());
        }
    }

    private void pinLaunchShortcut() {
        ShortcutManager sm = getSystemService(ShortcutManager.class);
        if (sm == null || !sm.isRequestPinShortcutSupported()) { toast("Your launcher can't pin shortcuts."); return; }
        Intent target = new Intent(ACTION_LAUNCH).setClassName(this, MainActivity.class.getName());
        ShortcutInfo info = new ShortcutInfo.Builder(this, "pin-launch")
            .setShortLabel("KiCad")
            .setLongLabel("Launch KiCad")
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(target)
            .build();
        sm.requestPinShortcut(info, null);
    }

    // ---- UI ----------------------------------------------------------------------------------

    private void render() {
        ScrollView sv = new ScrollView(this);
        sv.setBackgroundColor(BG);
        sv.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(24), dp(16), dp(24));
        sv.addView(root);

        TextView title = text("KiCad Launcher", 26, TEXT, true);
        root.addView(title);
        root.addView(text("Full desktop KiCad on this device, via Termux + Termux:X11.", 14, MUTED, false));
        root.addView(space(16));

        boolean termux = installed(TERMUX), x11 = installed(X11), widget = installed(WIDGET), perm = termux && permitted();

        LinearLayout status = card();
        status.addView(statusRow("Termux", termux, termux ? "installed" : "install from F-Droid or GitHub"));
        status.addView(statusRow("Termux:X11", x11, x11 ? "installed" : "install the Termux:X11 app (GitHub releases)"));
        status.addView(statusRow("Run-command permission", perm, perm ? "granted" : "grant it in step 1"));
        status.addView(statusRow("Termux:Widget (optional)", widget, widget ? "installed" : "not needed with the pinned icon below"));
        root.addView(status);
        root.addView(space(12));

        LinearLayout s1 = card();
        s1.addView(text("1  Allow this app to control Termux (once)", 16, TEXT, true));
        s1.addView(text("Copy the command, paste it in Termux, then come back and grant the permission.", 13, MUTED, false));
        s1.addView(mono(ENABLE_CMD));
        s1.addView(row(
            button("Copy command", v -> copy(ENABLE_CMD)),
            button("Open Termux", v -> open(TERMUX))));
        s1.addView(button("Grant permission", v -> {
            if (!termux) toast("Install Termux first.");
            else requestPermissions(new String[]{PERM_RUN}, 1);
        }));
        root.addView(s1);
        root.addView(space(12));

        LinearLayout s2 = card();
        s2.addView(text("2  Install KiCad (about 6 GB, 10-20 min)", 16, TEXT, true));
        s2.addView(check("3d", "Include 3D models (+3 GB)"));
        s2.addView(check("hidpi", "High-DPI screen (UI scale 2)"));
        s2.addView(check("virgl", "Experimental GPU path (virgl)"));
        s2.addView(button("Install in Termux", v -> {
            if (!perm) toast("Finish step 1 first.");
            else installKicad();
        }));
        root.addView(s2);
        root.addView(space(12));

        LinearLayout s3 = card();
        s3.addView(text("3  Use it", 16, TEXT, true));
        Button go = button("Launch KiCad", v -> launchKicad());
        go.setBackground(round(ACCENT, 12));
        go.setTextColor(BG);
        s3.addView(go);
        s3.addView(check("visible", "Show Termux while launching (for debugging)", true));
        s3.addView(row(
            button("Stop", v -> stopKicad()),
            button("Add icon to home screen", v -> pinLaunchShortcut())));
        s3.addView(text("Tip: in Termux:X11 preferences set Touch mode to \"Simulated touchscreen\"; "
            + "three-finger swipe down shows Esc/Ctrl/Alt keys. Projects and scripts live in Internal storage/KiCad.",
            12, MUTED, false));
        root.addView(s3);

        setContentView(sv);
    }

    private View message(String s) {
        LinearLayout l = new LinearLayout(this);
        l.setBackgroundColor(BG);
        l.setGravity(Gravity.CENTER);
        l.addView(text(s, 18, TEXT, false));
        return l;
    }

    private LinearLayout card() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(dp(14), dp(14), dp(14), dp(14));
        l.setBackground(round(CARD, 14));
        return l;
    }

    private View statusRow(String label, boolean ok, String hint) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.VERTICAL);
        r.setPadding(0, dp(4), 0, dp(4));
        r.addView(text((ok ? "● " : "○ ") + label, 15, ok ? ACCENT : BAD, false));
        r.addView(text(hint, 12, MUTED, false));
        return r;
    }

    private CheckBox check(String key, String label) { return check(key, label, false); }

    private CheckBox check(String key, String label, boolean def) {
        CheckBox c = new CheckBox(this);
        c.setText(label);
        c.setTextColor(TEXT);
        c.setChecked(prefs.getBoolean(key, def));
        c.setOnCheckedChangeListener((v, on) -> prefs.edit().putBoolean(key, on).apply());
        return c;
    }

    private View row(View a, View b) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1);
        r.addView(a, p);
        r.addView(b, new LinearLayout.LayoutParams(p));
        return r;
    }

    private Button button(String label, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextColor(TEXT);
        b.setBackground(round(Color.parseColor("#24493F"), 12));
        b.setOnClickListener(l);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        p.setMargins(dp(3), dp(4), dp(3), dp(4));
        b.setLayoutParams(p);
        return b;
    }

    private TextView text(String s, int sp, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(t.getTypeface(), android.graphics.Typeface.BOLD);
        t.setPadding(0, dp(2), 0, dp(2));
        return t;
    }

    private TextView mono(String s) {
        TextView t = text(s, 11, ACCENT, false);
        t.setTypeface(android.graphics.Typeface.MONOSPACE);
        t.setTextIsSelectable(true);
        t.setBackground(round(Color.parseColor("#0E1A17"), 8));
        t.setPadding(dp(8), dp(8), dp(8), dp(8));
        return t;
    }

    private View space(int h) {
        View v = new View(this);
        v.setLayoutParams(new LinearLayout.LayoutParams(1, dp(h)));
        return v;
    }

    private GradientDrawable round(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    private void copy(String s) {
        ((ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE))
            .setPrimaryClip(ClipData.newPlainText("kicad", s));
        toast("Copied");
    }

    private void open(String pkg) {
        Intent i = getPackageManager().getLaunchIntentForPackage(pkg);
        if (i == null) toast("Not installed: " + pkg); else startActivity(i);
    }

    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_LONG).show(); }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        super.onRequestPermissionsResult(code, perms, results);
        render();
    }
}
