# Latry by OB508 test features

This branch currently includes:

- Android floating talker overlay.
- `Latry by OB508` application branding and separate Android application ID.
- Gateway activity card on the Home screen.
- Live SvxReflector `OB...` user list from NODE_LIST / NODE_JOINED / NODE_LEFT.
- Protected dynamic gateway/source lists provided by SVXportal according to the authenticated user profile.
- Full FRN user details: display name, callsign, name, location, client type, raw FRN state, server count and update timestamp.
- Settings switches for showing SvxReflector and FRN users.
- FRN polling only while the FRN user list is enabled, refreshed every 15 seconds.
- The FRN endpoint has been verified from the public Internet without WireGuard.

This file also intentionally triggers a fresh Android debug build after the gateway-activity patch is applied.
