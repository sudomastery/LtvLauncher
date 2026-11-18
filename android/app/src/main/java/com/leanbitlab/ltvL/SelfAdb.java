package com.leanbitlab.ltvL;

import android.content.Context;

import java.io.File;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

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
 * Safety: only the packages in {@link #ALLOWED_PACKAGES} are accepted and only two fixed
 * commands are ever sent. Nothing else can be run through this class.
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
            File dir = context.getFilesDir();
            File privateKey = new File(dir, "adbkey");
            File publicKey = new File(dir, "adbkey.pub");
            if (!privateKey.exists() || !publicKey.exists()) {
                AdbKeyPair.generate(privateKey, publicKey);
            }
            AdbKeyPair keyPair = AdbKeyPair.read(privateKey, publicKey);

            // Only these two commands exist; packageName was checked against the allow list above.
            String command = enabled
                    ? "pm enable --user 0 " + packageName
                    : "pm disable-user --user 0 " + packageName;

            try (Dadb dadb = Dadb.create(HOST, PORT, keyPair)) {
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
}
