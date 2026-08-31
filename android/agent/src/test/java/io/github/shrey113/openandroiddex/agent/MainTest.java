package io.github.shrey113.openandroiddex.agent;

import org.junit.Test;

import static org.junit.Assert.assertFalse;

public class MainTest {
    @Test
    public void unsupportedControlBecomesACommandFailure() {
        assertFalse(Main.runCommand(
            () -> AgentCommand.deviceControl("airplaneMode", true)
        ));
    }
}
