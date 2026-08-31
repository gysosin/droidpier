# Contributing to DroidPier

Issues, documentation fixes, compatibility reports, and pull requests are welcome.
Read the [development guide](docs/DEVELOPMENT.md) before changing code.

For bugs, include the release version, desktop OS/architecture, Android version,
steps to reproduce, and expected versus actual behavior. Never upload pairing
codes, device serials, private app data, credentials, or raw device captures.
Use private security reporting for vulnerabilities, not public issues.

Keep changes focused. Discuss major interface or dependency changes in an issue
first. Add meaningful regression tests for behavioral fixes, run the relevant
analyzers/tests, and include screenshots for visible changes. Inspect generated
goldens before accepting them. The UI uses the public facade; device operations
belong in the backend and platform integration.

Contributions are accepted under the project's Apache-2.0 license. Preserve
copyright notices and disclose third-party code or assets and their licenses.
Do not submit proprietary recovered source or assets without redistribution rights.

The maintainer reviews releases and compatibility claims. A green compilation
alone does not establish working hardware integration.
