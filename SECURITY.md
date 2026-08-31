# Security policy

DroidPier is pre-release software. Only the newest published beta receives fixes;
there is no supported stable release yet.

Report suspected vulnerabilities through GitHub's private vulnerability reporting:
https://github.com/gysosin/droidpier/security/advisories/new
Do not put exploit details, credentials, pairing codes, device identifiers,
notification content, or clipboard data into public issues.

Include the affected version, platform, impact, and minimal reproduction using
synthetic data. There is no guaranteed response SLA or paid bug bounty.

DroidPier requires an authorized Android debugging connection. Trust only your
own computers, revoke unused debugging authorizations, and never expose ADB or
wireless debugging to the internet. Application communication uses session tokens
and loopback listeners carried through ADB. No root access is required.

Release-signing keys are kept outside Git and are unavailable to pull-request
builds. Verify release checksums before installing. Checksums detect corruption;
they do not replace a trusted publisher signature or independent security review.
