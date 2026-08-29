# Latry by OB508 test features

This branch currently includes:

- Android floating talker overlay.
- `Latry by OB508` application branding and separate Android application ID.
- Gateway activity card on the Home screen.
- Live SvxReflector `OB...` user list from NODE_LIST / NODE_JOINED / NODE_LEFT.
- Optional FRN user list from `https://svxportal.pmr446.si/frn_users.json`.
- Settings switches for showing SvxReflector and FRN users.
- FRN polling only while the FRN user list is enabled, refreshed every 15 seconds.

This file also intentionally triggers a fresh Android debug build after the gateway-activity patch is applied.
