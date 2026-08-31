package io.github.shrey113.openandroiddex.agent;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

public class AgentCommandTest {
    @Test
    public void launchUsesAnArgumentArray() {
        ProcessBuilder builder = AgentCommand.processFor("app.launch", "com.example.demo");

        assertEquals("/system/bin/monkey", builder.command().get(0));
        assertEquals("com.example.demo", builder.command().get(2));
    }

    @Test
    public void invalidPackageIsRejected() {
        assertThrows(
            IllegalArgumentException.class,
            () -> AgentCommand.processFor("app.launch", "com.example;rm")
        );
    }

    @Test
    public void applicationListingUsesTheFixedPackageManagerCommand() {
        ProcessBuilder builder = AgentCommand.processFor("apps.list", null);

        assertEquals("/system/bin/cmd", builder.command().get(0));
        assertEquals("query-activities", builder.command().get(2));
    }

    @Test
    public void controlCommandsMapOnlyToFixedArgumentArrays() {
        assertEquals(
            "play-pause",
            AgentCommand.mediaAction("playPause").command().get(3)
        );
        assertEquals("3", AgentCommand.setVolume("music", 7).command().get(4));
        assertEquals(
            "disabled",
            AgentCommand.deviceControl("wifi", false).command().get(3)
        );
        assertEquals(
            "enable",
            AgentCommand.deviceControl("airplaneMode", true).command().get(3)
        );
        assertEquals(
            "enable",
            AgentCommand.deviceControl("mobileData", true).command().get(2)
        );
        assertEquals(
            "true",
            AgentCommand.deviceControl("location", true).command().get(3)
        );
        assertThrows(
            IllegalArgumentException.class,
            () -> AgentCommand.deviceControl("torch", true)
        );
    }

    @Test
    public void permissionSettingsAreAllowlisted() {
        assertEquals(
            "android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS",
            AgentCommand.openPermissionSettings("notifications").command().get(3)
        );
        assertThrows(
            IllegalArgumentException.class,
            () -> AgentCommand.openPermissionSettings("unknown")
        );
    }
}
