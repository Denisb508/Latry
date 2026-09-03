# 📱 Latry by OB508

[![Android Debug Build](https://github.com/Denisb508/Latry/actions/workflows/android-debug-build.yml/badge.svg?branch=feature%2Ftalker-pip-overlay)](https://github.com/Denisb508/Latry/actions/workflows/android-debug-build.yml)
[![Qt](https://img.shields.io/badge/Qt-6.9%2B-41CD52?logo=qt&logoColor=white)](https://www.qt.io/)
[![License](https://img.shields.io/badge/License-GPLv3-blue)](LICENSE)
[![Public](https://img.shields.io/badge/GitHub-Public-success?logo=github)](https://github.com/Denisb508/Latry)

**Latry by OB508** is an extended fork of the original Latry mobile SvxLink client, focused on tighter integration with **SvxReflector, SVXportal, FRN, DMR, VoIP and radio gateway infrastructure**.

The project keeps the lightweight PTT/VoIP experience of Latry while adding live activity information, gateway awareness, GEO features and centrally controlled functionality for managed radio networks.

> 🚧 Active development takes place on the [`feature/talker-pip-overlay`](https://github.com/Denisb508/Latry/tree/feature/talker-pip-overlay) branch. Some features described as **In development** are not yet part of `main`.

## 📥 Android test build

Current Android test builds are published through the SVXportal application page:

**➡️ [Download Latry by OB508 APK](https://svxportal.pmr446.si/apps.php)**

The OB508 Android builds use a stable application signing key and increasing Android `versionCode`, allowing subsequent builds to be installed as normal app updates.

## ✨ OB508 additions

### 🎙️ Live Talker & Last Talker

- Shows the currently active talker in real time.
- Keeps the last talker visible after transmission ends.
- Extended handling for gateway/activity sources, including DMR paths.

### 🪟 Talker PiP / compact activity view

- Compact talker presentation designed to remain useful while navigating other parts of the app.
- Development branch dedicated to the Talker PiP and related activity UI improvements.

### 🌉 PREHODI — gateway activity

- Displays FRN, DMR and other portal-defined gateways.
- Compact view prioritizes the two most recently active gateways.
- Expandable list provides access to additional gateways.
- Gateway entries can expose their current users/activity when provided by SVXportal.

### 🔄 Dynamic SVXportal sources

Latry by OB508 can consume portal-defined sources instead of requiring every source to be hard-coded in the mobile application.

Examples include:

- SvxReflector activity
- FRN gateways
- DMR gateways
- GEO sources
- VoIP / FreePBX integration status
- future radio/IP gateway sources

### ☎️ VoIP / FreePBX / Zoiper / GSM integration

The wider **Latry by OB508 + SVXportal/SVXlink** environment is also integrated with **FreePBX** and SIP/VoIP services. This makes it possible to connect radio-network functions with conventional VoIP clients and telephony gateways.

Supported or implemented integration scenarios include:

- 📞 **local internal SIP calls** between FreePBX extensions;
- 📱 use of **Zoiper** and other SIP softphones as normal FreePBX clients;
- 📡 **GSM gateway/interface integration** for bridging GSM telephony into the FreePBX environment;
- 👥 **Conference mode** using FreePBX/ConfBridge;
- 🎙️ connection of radio/SVXlink paths into a conference where required;
- 🔇 independent RX/TX control for selected conference/radio legs;
- 🔢 DTMF-based control of conference functions;
- 🔄 possibility to route selected SVXlink talkgroups into dedicated VoIP conferences;
- 🏠 local/internal calling that can continue independently of the public telephone network when the local VoIP infrastructure is available.

This allows the same infrastructure to combine **Latry, SvxReflector/SVXlink, FreePBX, Zoiper, GSM gateways and conference rooms** while keeping each transport layer independently manageable.

Latry itself remains focused on the SvxReflector/mobile-radio client role; SIP call handling and conference control are provided by the integrated FreePBX/SVXportal infrastructure.

### 🗺️ Latry GEO

- Interactive OpenStreetMap-based map.
- Single-finger pan and pinch zoom.
- Automatic first-load viewport fitting without repeatedly forcing the map back after the user pans or zooms.
- Invalid or missing coordinates are ignored instead of being rendered at `0,0`.
- Supports portal-managed location modes such as **Off / City / Precise**.

### 🛡️ SVXportal-managed capabilities

The OB508 fork is being extended with server-controlled capabilities. The goal is for an administrator to decide which functions are available to a user or group rather than enabling every feature globally.

Existing and planned capability areas include GEO sharing, precise location, live tracking, background tracking, history and moderation controls.

### 📲 Android update flow

The custom Android workflow includes:

- automated Qt/Android build on GitHub Actions;
- stable OB508 APK signing;
- monotonically increasing Android `versionCode`;
- downloadable test APK artifacts.

## 🚧 In development

### 🚗 Live Tracking

Live Tracking is currently being developed on top of the existing Latry GEO update path.

Planned user-selectable tracking modes:

- 🧠 **Smart** — default; adapts the reporting interval to movement
- ⚡ **10 s**
- 🚗 **15 s**
- 🕒 **30 s**
- 🔋 **60 s**

Tracking availability is intended to be controlled by SVXportal permissions. Background tracking and route history are planned as separate capabilities.

### 📡 Radijski prenos koordinat / RF Packet Gateway

A planned extension of Latry by OB508 is an **offline RF coordinate and packet gateway**. The goal is to allow two Latry devices to exchange coordinates and short status packets through conventional radio equipment even when there is **no Internet connection**.

The intended concept is:

```text
Latry phone
    │
    │ Wi-Fi connection to a local access point
    │ Internet connection is not required
    ▼
RF Gateway / Hotspot
Raspberry Pi-class device
    │
    │ AIOC / USB audio / PTT interface
    ▼
Radio transceiver
    │
    │ RF data transmission
    │ packet / AFSK / PSK / other suitable modem mode
    ▼
Radio transceiver
    │
    ▼
RF Gateway / Hotspot
Raspberry Pi-class device + AIOC
    │
    │ local Wi-Fi
    ▼
Latry phone
```

In this mode the radio stations act only as the **RF transport layer**. Latry prepares the coordinate/status data, the local gateway converts the packet into a radio-compatible modem signal, and the receiving gateway converts it back for Latry.

Planned capabilities include:

- 📍 **coordinate transfer without Internet**;
- 🚗 **offline RF tracking** between mobile Latry users;
- 📦 short packet/status messages;
- 🧭 callsign, timestamp, position and optional movement data;
- 🔄 automatic delivery of received coordinates directly to the Latry GEO map;
- 📶 local Wi-Fi AP mode so the phone only needs connectivity to the RF gateway;
- 🌐 optional hybrid mode where the same gateway can use RF locally and SVXportal/Internet when connectivity is available;
- 🔁 support for simplex links as well as gateway/repeater-style deployments where authorized.

The packet format and RF modem are intentionally not fixed yet. Candidate modes include compact packet/AFSK-style signalling or a suitable PSK/data mode, with the final choice based on reliability, occupied bandwidth, radio compatibility and real-world testing.

#### 🔧 RF gateway test platform

The planned test platform is based on a **Raspberry Pi-class gateway**, **AIOC or equivalent audio/PTT interface**, optional **SDR monitoring**, and a compatible analog or digital radio transceiver. Specific radio models are intentionally not tied to the design.

The RF side is intended for operation only on frequencies and services where the operator is authorized to transmit, including the project's licensed/allocated radio resources and future authorized simplex channels, subject to applicable radio regulations.

### 🛡️ Moderator roles

A granular moderation model is also being designed so operational moderators do not require full administrator access.

Planned separation includes:

- **Moderator** — operational user controls such as TX/RX prohibit and permitted group assignment;
- **GEO Moderator** — GEO/tracking visibility and permitted tracking controls;
- **Administrator** — full Latry/SVXportal management.

GEO access is intentionally separated from normal user moderation for privacy.

## 📸 Screenshots

Screenshots of the OB508 Talker, PREHODI and GEO interfaces will be added here as the current development UI is finalized.

## 📱 Original Latry capabilities

Latry provides the core mobile SvxLink client functionality on which this fork is based:

- SvxReflector connectivity
- Opus audio
- Push-to-talk operation
- talkgroup support
- callsign/key authentication
- Android and iOS codebases
- Android foreground/background operation
- lightweight Qt-based interface

## 🏗️ Project structure

```text
Latry/
├── android/                    # Android Qt application
│   ├── android/                # Android manifest, Java services and resources
│   ├── CMakeLists.txt
│   ├── Main.qml
│   ├── HomePage.qml
│   ├── MapPage.qml
│   └── ReflectorClient.*
├── iOS/                        # iOS application sources
├── .github/workflows/          # Automated Android build
└── README.md
```

## 🛠️ Development

The Android build currently targets Qt 6.9+ APIs, with the GitHub Actions development workflow using a current Qt Android toolchain.

Typical local Android configuration requires:

- Qt 6.9+
- Android SDK / NDK
- CMake
- JDK
- Opus dependencies included by the project

For active OB508 work, check out:

```bash
git clone https://github.com/Denisb508/Latry.git
cd Latry
git checkout feature/talker-pip-overlay
```

## 🔗 Project links

- **Latry by OB508 repository:** https://github.com/Denisb508/Latry
- **OB508 development branch:** https://github.com/Denisb508/Latry/tree/feature/talker-pip-overlay
- **Android build workflow:** https://github.com/Denisb508/Latry/actions/workflows/android-debug-build.yml
- **SVXportal APK page:** https://svxportal.pmr446.si/apps.php
- **Original Latry website:** https://latry.app
- **Original upstream repository:** https://github.com/s1lviu/Latry

## 🙏 Upstream credit

Latry by OB508 is a fork of **Latry**, originally developed by **Silviu / YO6SAY**.

The OB508 fork builds on that project and adds integrations and functionality developed for the SVXportal/SvxReflector/FRN/DMR environment.

Please also visit and support the upstream project:

**https://github.com/s1lviu/Latry**

## 📄 License

This repository remains licensed under the **GNU General Public License v3.0 (GPLv3)**, consistent with the upstream Latry project.

See [`LICENSE`](LICENSE) for the full license text.

---

**Latry by OB508** — experimental radio-network integration and mobile client development for the amateur radio community. 📻
