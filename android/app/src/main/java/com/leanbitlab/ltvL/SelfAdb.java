package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

import dadb.AdbKeyPair;
import dadb.AdbShellResponse;
import dadb.Dadb;

/**
 * Lets the launcher enable or disable a small, fixed list of apps by talking to the TV's own
 * network debugging service (adbd on 127.0.0.1:5555), the same way a computer running
 * "adb shell pm disable-user" would. A normal app is not allowed to do this directly.
 *
 * Requirements: Network debugging is on (Developer options), and the TV's "Allow debugging?"
 * prompt was accepted once for this launcher's key (choose "Always allow").
 *
 * Safety: only fixed commands are ever sent. Enabling or disabling is limited to the packages in
 * {@link #ALLOWED_PACKAGES}. Force closing is limited to apps that have a launcher icon and are not
 * protected (see {@link #isProtected}). Updating is limited to an APK inside this app's own update folder
 * whose SHA-256 matches. Nothing else can be run through this class.
 */
final class SelfAdb {
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 5555;

    /** Apps the launcher may switch off and on. Keep this list short and obviously safe to disable. */
    static final Set<String> ALLOWED_PACKAGES =
            Collections.unmodifiableSet(new HashSet<>(Arrays.asList("com.android.vending")));

    private SelfAdb() {}

    static Map<String, Object> setPackageEnabled(Context context, String packageName, boolean enabled) {
        Map<String, Object> out = new HashMap<>();
        if (packageName == null || !ALLOWED_PACKAGES.contains(packageName)) {
            out.put("ok", false);
            out.put("message", "This app is not on the list of apps the launcher may change.");
            return out;
        }
        try {
            // Only these two commands exist; packageName was checked against the allow list above.
            String command = enabled
                    ? "pm enable --user 0 " + packageName
                    : "pm disable-user --user 0 " + packageName;

            try (Dadb dadb = connect(context)) {
                AdbShellResponse response = dadb.shell(command);
                boolean ok = response.getExitCode() == 0;
                out.put("ok", ok);
                out.put("message", response.getAllOutput().trim());
            }
        } catch (Exception e) {
            out.put("ok", false);
            out.put("message", e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage()));
        }
        return out;
    }

    // ----- Force close and "Optimize mode" -----

    private static final Pattern PACKAGE_NAME = Pattern.compile("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$");

    /** Packages that must never be closed from here, besides everything under com.tcl. and com.android. */
    private static final Set<String> PROTECTED_PACKAGES = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "android",
            "com.google.android.tungsten.setupwraith",
            "com.google.android.gms",
            "com.google.android.gsf")));

    /** True for the launcher itself, the TV's system software and anything we cannot be sure is a normal app. */
    static boolean isProtected(Context context, String packageName) {
        if (packageName == null || !PACKAGE_NAME.matcher(packageName).matches()) return true;
        if (packageName.equals(context.getPackageName())) return true;
        if (PROTECTED_PACKAGES.contains(packageName)) return true;
        if (packageName.startsWith("com.tcl.")) return true;
        // The Play Store is a normal app people may want to close.
        if (packageName.startsWith("com.android.") && !packageName.equals("com.android.vending")) return true;
        return false;
    }

    /** Packages with an icon in the launcher, i.e. apps a person opens, as opposed to background services. */
    static Set<String> launchablePackages(Context context) {
        PackageManager pm = context.getPackageManager();
        Set<String> out = new HashSet<>();
        for (String category : new String[]{Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER}) {
            Intent intent = new Intent(Intent.ACTION_MAIN).addCategory(category);
            for (android.content.pm.ResolveInfo info : pm.queryIntentActivities(intent, 0)) {
                if (info.activityInfo != null) out.add(info.activityInfo.packageName);
            }
        }
        return out;
    }

    /** "com.foo.bar:service" -> "com.foo.bar". */
    static String packageOfProcess(String processName) {
        int colon = processName.indexOf(':');
        return colon < 0 ? processName : processName.substring(0, colon);
    }

    private static Dadb connect(Context context) throws Exception {
        File dir = context.getFilesDir();
        File privateKey = new File(dir, "adbkey");
        File publicKey = new File(dir, "adbkey.pub");
        if (!privateKey.exists() || !publicKey.exists()) {
            AdbKeyPair.generate(privateKey, publicKey);
        }
        return Dadb.create(HOST, PORT, AdbKeyPair.read(privateKey, publicKey));
    }

    /** Force stops one app (the equivalent of "adb shell am force-stop"). */
    static Map<String, Object> forceStop(Context context, String packageName) {
        Map<String, Object> out = new HashMap<>();
        if (isProtected(context, packageName) || !launchablePackages(context).contains(packageName)) {
            out.put("ok", false);
            out.put("message", "This app cannot be closed from the launcher.");
            return out;
        }
        try (Dadb dadb = connect(context)) {
            AdbShellResponse response = dadb.shell("am force-stop " + packageName);
            out.put("ok", response.getExitCode() == 0);
            out.put("message", response.getAllOutput().trim());
        } catch (Exception e) {
            out.put("ok", false);
            out.put("message", e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage()));
        }
        return out;
    }

    /**
     * Optimize mode: force stops every other running app that has a launcher icon, so only
     * {@code keepPackage} (and the system) is left. Returns the list of packages that were closed.
     */
    static Map<String, Object> closeAllExcept(Context context, String keepPackage) {
        Map<String, Object> out = new HashMap<>();
        List<String> closed = new ArrayList<>();
        out.put("closed", closed);
        try (Dadb dadb = connect(context)) {
            Set<String> launchable = launchablePackages(context);
            AdbShellResponse running = dadb.shell("ps -A -o NAME");
            Set<String> targets = new HashSet<>();
            for (String line : running.getOutput().split("\n")) {
                String name = line.trim();
                if (name.isEmpty()) continue;
                String pkg = packageOfProcess(name);
                if (!pkg.equals(keepPackage) && launchable.contains(pkg) && !isProtected(context, pkg)) {
                    targets.add(pkg);
                }
            }
            for (String pkg : targets) {
                AdbShellResponse response = dadb.shell("am force-stop " + pkg);
                if (response.getExitCode() == 0) closed.add(pkg);
            }
            out.put("ok", true);
            out.put("message", "");
        } catch (Exception e) {
            out.put("ok", false);
            out.put("message", e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage()));
        }
        return out;
    }

    // ----- Self update -----

    /** The only folder an update APK may be installed from (inside this app's own external files folder). */
    static File updateDirectory(Context context) {
        File base = context.getExternalFilesDir(null);
        return new File(base, "update");
    }

    /** Plain file names only: the path is placed inside a shell command, so no quotes, spaces or $ are allowed. */
    private static final Pattern UPDATE_FILE_NAME = Pattern.compile("^[A-Za-z0-9._-]+\\.apk$");

    static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) > 0) digest.update(buffer, 0, read);
        }
        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) hex.append(String.format("%02x", b));
        return hex.toString();
    }

    /**
     * Installs a downloaded update over the running app ("pm install -r"). Android itself refuses the APK
     * unless it is signed with the same key as the installed app, so only releases signed by the owner apply.
     * The file must sit in the update folder, be a .apk, and match {@code expectedSha256}.
     */
    static Map<String, Object> installUpdate(Context context, String path, String expectedSha256) {
        Map<String, Object> out = new HashMap<>();
        try {
            File apk = new File(path).getCanonicalFile();
            File folder = updateDirectory(context).getCanonicalFile();
            if (!apk.getPath().startsWith(folder.getPath() + File.separator)
                    || !UPDATE_FILE_NAME.matcher(apk.getName()).matches() || !apk.isFile()) {
                out.put("ok", false);
                out.put("message", "The update file is not where it should be.");
                return out;
            }
            if (expectedSha256 == null || !sha256(apk).equalsIgnoreCase(expectedSha256.trim())) {
                out.put("ok", false);
                out.put("message", "The downloaded update does not match its checksum.");
                return out;
            }
            try (Dadb dadb = connect(context)) {
                AdbShellResponse response = dadb.shell("pm install -r \"" + apk.getPath() + "\"");
                String text = response.getAllOutput().trim();
                out.put("ok", response.getExitCode() == 0 && text.contains("Success"));
                out.put("message", text);
            }
        } catch (Exception e) {
            // The old process is replaced while "pm install" runs, so a dropped connection can be a success.
            out.put("ok", false);
            out.put("message", e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage()));
        }
        return out;
    }
}
