package io.github.shrey113.openandroiddex.agent;

import java.util.regex.Pattern;

final class AgentCommand {
    private static final Pattern PACKAGE = Pattern.compile("^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z][A-Za-z0-9_]*)+$");

    private AgentCommand() {}

    static ProcessBuilder processFor(String type, String packageName) {
        return switch (type) {
            case "apps.list" -> new ProcessBuilder(
                "/system/bin/cmd", "package", "query-activities", "--brief",
                "-a", "android.intent.action.MAIN",
                "-c", "android.intent.category.LAUNCHER"
            );
            case "app.launch" -> packageCommand(
                packageName,
                "/system/bin/monkey", "-p", packageName, "-c",
                "android.intent.category.LAUNCHER", "1"
            );
            case "app.force_stop" -> packageCommand(
                packageName,
                "/system/bin/am", "force-stop", packageName
            );
            default -> throw new IllegalArgumentException("Unsupported command type");
        };
    }

    static ProcessBuilder mediaAction(String action) {
        String key = switch (action) {
            case "previous" -> "previous";
            case "playPause" -> "play-pause";
            case "next" -> "next";
            default -> throw new IllegalArgumentException("Unsupported media action");
        };
        return new ProcessBuilder("/system/bin/cmd", "media_session", "dispatch", key);
    }

    static ProcessBuilder setVolume(String stream, int value) {
        int streamId = switch (stream) {
            case "voiceCall" -> 0;
            case "system" -> 1;
            case "ring" -> 2;
            case "music" -> 3;
            case "alarm" -> 4;
            case "notification" -> 5;
            default -> throw new IllegalArgumentException("Unsupported audio stream");
        };
        if (value < 0 || value > 100) {
            throw new IllegalArgumentException("Volume is out of range");
        }
        return new ProcessBuilder(
            "/system/bin/cmd", "media_session", "volume",
            "--stream", Integer.toString(streamId), "--set", Integer.toString(value)
        );
    }

    static ProcessBuilder deviceControl(String control, boolean enabled) {
        return switch (control) {
            case "wifi" -> new ProcessBuilder(
                "/system/bin/cmd", "wifi", "set-wifi-enabled",
                enabled ? "enabled" : "disabled"
            );
            case "bluetooth" -> new ProcessBuilder(
                "/system/bin/cmd", "bluetooth_manager", enabled ? "enable" : "disable"
            );
            case "rotationLock" -> new ProcessBuilder(
                "/system/bin/settings", "put", "system", "accelerometer_rotation",
                enabled ? "0" : "1"
            );
            case "airplaneMode" -> new ProcessBuilder(
                "/system/bin/cmd", "connectivity", "airplane-mode",
                enabled ? "enable" : "disable"
            );
            case "mobileData" -> new ProcessBuilder(
                "/system/bin/svc", "data", enabled ? "enable" : "disable"
            );
            case "location" -> new ProcessBuilder(
                "/system/bin/cmd", "location", "set-location-enabled",
                enabled ? "true" : "false"
            );
            default -> throw new IllegalArgumentException("Unsupported device control");
        };
    }

    static ProcessBuilder openPermissionSettings(String capability) {
        if (!"notifications".equals(capability)) {
            throw new IllegalArgumentException("Unsupported permission settings");
        }
        return new ProcessBuilder(
            "/system/bin/am", "start", "-a",
            "android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"
        );
    }

    private static ProcessBuilder packageCommand(String packageName, String... command) {
        if (packageName == null || !PACKAGE.matcher(packageName).matches()) {
            throw new IllegalArgumentException("Invalid Android package name");
        }
        return new ProcessBuilder(command);
    }
}
