package io.github.shrey113.openandroiddex.agent;

import org.json.JSONObject;
import org.json.JSONArray;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.lang.reflect.InvocationTargetException;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

public final class Main {
    private static final Pattern TOKEN = Pattern.compile("^[A-Za-z0-9_-]{32,128}$");
    private static final Pattern COMPONENT = Pattern.compile(
        "^\\s*([A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z][A-Za-z0-9_]*)+)/[^\\s]+$"
    );

    private Main() {}

    public static void main(String[] args) throws Exception {
        Configuration configuration = Configuration.parse(args);
        ApplicationMetadataReader applicationMetadata = null;
        try {
            applicationMetadata = ApplicationMetadataReader.create();
        } catch (Exception error) {
            Throwable cause = error instanceof InvocationTargetException && error.getCause() != null
                ? error.getCause()
                : error;
            String detail = cause.getMessage();
            System.err.println(
                "application metadata unavailable: " + cause.getClass().getSimpleName() +
                (detail == null || detail.isBlank() ? "" : ": " + detail)
            );
        }
        while (!Thread.currentThread().isInterrupted()) {
            try {
                runSession(configuration, applicationMetadata);
            } catch (Exception error) {
                System.err.println("agent session ended: " + error.getClass().getSimpleName());
                Thread.sleep(2000);
            }
        }
    }

    private static void runSession(
        Configuration configuration,
        ApplicationMetadataReader applicationMetadata
    ) throws Exception {
        ClipboardBridge clipboard = null;
        try {
            clipboard = ClipboardBridge.create();
        } catch (Exception error) {
            Throwable cause = error instanceof InvocationTargetException && error.getCause() != null
                ? error.getCause()
                : error;
            System.err.println("clipboard unavailable: " + cause.getClass().getSimpleName());
        }
        try (Socket socket = new Socket(InetAddress.getLoopbackAddress(), configuration.port());
             BufferedReader input = new BufferedReader(new InputStreamReader(
                 socket.getInputStream(), StandardCharsets.UTF_8));
             BufferedWriter output = new BufferedWriter(new OutputStreamWriter(
                 socket.getOutputStream(), StandardCharsets.UTF_8))) {
            socket.setKeepAlive(true);
            JSONArray capabilities = new JSONArray()
                .put("apps.list")
                .put("app.launch")
                .put("app.force_stop")
                .put("media.action")
                .put("volume.set")
                .put("device.control")
                .put("permission.settings");
            if (clipboard != null) {
                capabilities.put("clipboard.get").put("clipboard.set");
            }
            send(output, "agent.hello", new JSONObject()
                .put("sessionToken", configuration.token())
                .put("capabilities", capabilities));
            String line;
            while ((line = input.readLine()) != null) {
                handle(line, output, clipboard, applicationMetadata);
            }
        }
    }

    private static void handle(
        String line,
        BufferedWriter output,
        ClipboardBridge clipboard,
        ApplicationMetadataReader applicationMetadata
    ) throws Exception {
        JSONObject message = new JSONObject(line);
        if (message.optInt("v") != 1) return;
        String type = message.optString("type");
        if ("ping".equals(type)) {
            send(output, "pong", new JSONObject().put("replyTo", message.optString("id")));
            return;
        }
        if ("apps.list".equals(type)) {
            Process process = AgentCommand.processFor(type, null)
                .redirectErrorStream(true)
                .start();
            JSONArray applications = readApplications(process, applicationMetadata);
            int exitCode = process.waitFor();
            send(output, "apps.result", new JSONObject()
                .put("replyTo", message.optString("id"))
                .put("success", exitCode == 0)
                .put("applications", applications));
            return;
        }
        if ("clipboard.get".equals(type)) {
            boolean success = clipboard != null;
            String text = "";
            if (success) {
                try {
                    text = clipboard.readText();
                } catch (Exception error) {
                    success = false;
                }
            }
            send(output, "clipboard.result", new JSONObject()
                .put("replyTo", message.optString("id"))
                .put("success", success)
                .put("text", text));
            return;
        }
        if ("clipboard.set".equals(type)) {
            JSONObject data = message.optJSONObject("data");
            String text = data == null ? null : data.optString("text", null);
            boolean success = clipboard != null && text != null;
            if (success) {
                try {
                    clipboard.writeText(text);
                } catch (Exception error) {
                    success = false;
                }
            }
            send(output, "command.result", new JSONObject()
                .put("replyTo", message.optString("id"))
                .put("success", success));
            return;
        }
        if ("app.launch".equals(type) || "app.force_stop".equals(type)) {
            JSONObject data = message.optJSONObject("data");
            String packageName = data == null ? null : data.optString("packageName");
            boolean success = runCommand(() -> AgentCommand.processFor(type, packageName));
            send(output, "command.result", new JSONObject()
                .put("replyTo", message.optString("id"))
                .put("success", success));
            return;
        }
        if ("media.action".equals(type) ||
            "volume.set".equals(type) ||
            "device.control".equals(type) ||
            "permission.settings".equals(type)) {
            JSONObject data = message.optJSONObject("data");
            boolean success = data != null && runCommand(() -> switch (type) {
                case "media.action" -> AgentCommand.mediaAction(data.optString("action"));
                case "volume.set" -> AgentCommand.setVolume(
                    data.optString("stream"), data.optInt("value", -1)
                );
                case "device.control" -> AgentCommand.deviceControl(
                    data.optString("control"), data.optBoolean("enabled")
                );
                case "permission.settings" -> AgentCommand.openPermissionSettings(
                    data.optString("capability")
                );
                default -> throw new IllegalArgumentException("Unsupported command type");
            });
            send(output, "command.result", new JSONObject()
                .put("replyTo", message.optString("id"))
                .put("success", success));
        }
    }

    static boolean runCommand(CommandFactory command) {
        try {
            Process process = command.create().redirectErrorStream(true).start();
            return process.waitFor() == 0;
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            return false;
        } catch (Exception error) {
            return false;
        }
    }

    @FunctionalInterface
    interface CommandFactory {
        ProcessBuilder create();
    }

    private static JSONArray readApplications(
        Process process,
        ApplicationMetadataReader applicationMetadata
    ) throws Exception {
        Set<String> packages = new LinkedHashSet<>();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
            process.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                var match = COMPONENT.matcher(line);
                if (match.matches()) packages.add(match.group(1));
            }
        }
        JSONArray applications = new JSONArray();
        for (String packageName : packages) {
            applications.put(applicationMetadata == null
                ? new JSONObject()
                    .put("packageName", packageName)
                    .put("label", packageName)
                : applicationMetadata.describe(packageName));
        }
        return applications;
    }

    private static void send(BufferedWriter output, String type, JSONObject data) throws Exception {
        JSONObject envelope = new JSONObject()
            .put("v", 1)
            .put("id", UUID.randomUUID().toString())
            .put("type", type)
            .put("timestamp", Instant.now().toString())
            .put("data", data);
        output.write(envelope.toString());
        output.newLine();
        output.flush();
    }

    private static final class Configuration {
        private final String token;
        private final int port;

        private Configuration(String token, int port) {
            this.token = token;
            this.port = port;
        }

        String token() {
            return token;
        }

        int port() {
            return port;
        }

        static Configuration parse(String[] args) {
            String token = null;
            int port = 3698;
            for (int index = 0; index < args.length - 1; index += 2) {
                switch (args[index]) {
                    case "--token" -> token = args[index + 1];
                    case "--port" -> port = Integer.parseInt(args[index + 1]);
                    default -> throw new IllegalArgumentException("Unknown argument");
                }
            }
            if (token == null || !TOKEN.matcher(token).matches()) {
                throw new IllegalArgumentException("A valid session token is required");
            }
            if (port < 1 || port > 65535) {
                throw new IllegalArgumentException("Port is out of range");
            }
            return new Configuration(token, port);
        }
    }
}
