package io.github.shrey113.openandroiddex.agent;

import android.content.ClipData;
import android.os.IBinder;

import java.lang.reflect.Method;

final class ClipboardBridge {
    private static final int MAX_TEXT_LENGTH = 65_536;
    private static final String SHELL_PACKAGE = "com.android.shell";

    private final Object service;
    private final Method getPrimaryClip;
    private final Method setPrimaryClip;

    private ClipboardBridge(
        Object service,
        Method getPrimaryClip,
        Method setPrimaryClip
    ) {
        this.service = service;
        this.getPrimaryClip = getPrimaryClip;
        this.setPrimaryClip = setPrimaryClip;
    }

    static ClipboardBridge create() throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Method getService = serviceManager.getDeclaredMethod("getService", String.class);
        IBinder binder = (IBinder) getService.invoke(null, "clipboard");
        if (binder == null) throw new IllegalStateException("Clipboard service unavailable");

        Class<?> stub = Class.forName("android.content.IClipboard$Stub");
        Method asInterface = stub.getDeclaredMethod("asInterface", IBinder.class);
        Object clipboard = asInterface.invoke(null, binder);
        Method getter = findMethod(clipboard, "getPrimaryClip", false);
        Method setter = findMethod(clipboard, "setPrimaryClip", true);
        getter.setAccessible(true);
        setter.setAccessible(true);
        return new ClipboardBridge(clipboard, getter, setter);
    }

    String readText() throws Exception {
        Object value = getPrimaryClip.invoke(service, argumentsFor(getPrimaryClip, null));
        if (!(value instanceof ClipData clip) || clip.getItemCount() == 0) return "";
        CharSequence item = clip.getItemAt(0).getText();
        if (item == null) return "";
        String text = item.toString();
        return text.length() <= MAX_TEXT_LENGTH
            ? text
            : text.substring(0, MAX_TEXT_LENGTH);
    }

    void writeText(String text) throws Exception {
        if (text == null || text.length() > MAX_TEXT_LENGTH) {
            throw new IllegalArgumentException("Clipboard text is too large");
        }
        ClipData clip = ClipData.newPlainText("DroidPier", text);
        setPrimaryClip.invoke(service, argumentsFor(setPrimaryClip, clip));
    }

    private static Method findMethod(Object service, String name, boolean needsClip) {
        for (Method method : service.getClass().getMethods()) {
            if (!method.getName().equals(name)) continue;
            Class<?>[] parameters = method.getParameterTypes();
            if (!needsClip || (parameters.length > 0 && parameters[0] == ClipData.class)) {
                return method;
            }
        }
        throw new IllegalStateException(name + " is unavailable");
    }

    private static Object[] argumentsFor(Method method, ClipData clip) {
        Class<?>[] types = method.getParameterTypes();
        Object[] arguments = new Object[types.length];
        int stringIndex = 0;
        for (int index = 0; index < types.length; index++) {
            Class<?> type = types[index];
            if (type == ClipData.class) {
                arguments[index] = clip;
            } else if (type == String.class) {
                arguments[index] = stringIndex++ == 0 ? SHELL_PACKAGE : null;
            } else if (type == int.class) {
                arguments[index] = 0;
            } else if (type == long.class) {
                arguments[index] = 0L;
            } else if (type == boolean.class) {
                arguments[index] = false;
            } else {
                throw new IllegalStateException(
                    "Unsupported clipboard argument: " + type.getName()
                );
            }
        }
        return arguments;
    }
}
