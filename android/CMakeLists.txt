cmake_minimum_required(VERSION 3.16)

project(latry VERSION 0.0.19 LANGUAGES CXX)

set(LATRY_VERSION_NAME "${PROJECT_VERSION}")
set(LATRY_VERSION_CODE 33)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)
include(CTest)

set(LATRY_CORE_SOURCES
    ReflectorClient.cpp
    ReflectorClientConnection.cpp
    ReflectorClientProtocol.cpp
    ReflectorClientUdp.cpp
    ReflectorClientPtt.cpp
    ReflectorClientRecovery.cpp
    ReflectorClientJni.cpp
    AudioEngine.cpp
    AudioEngineRecording.cpp
    AudioEnginePlayback.cpp
    AudioEngineFocus.cpp
    AndroidAudioRecordInput.cpp
    AndroidAudioTrackOutput.cpp
    AndroidAudioRouteInterop.cpp
    AudioLimiter.cpp
    AudioJitterBuffer.cpp
    AudioStreamDevice.cpp
    OpusWrapper.cpp
    Resampler.cpp
)

set(LATRY_APP_SOURCES
    main.cpp
    ${LATRY_CORE_SOURCES}
    BatteryOptimizationHandler.cpp
    SppPttBridge.cpp
    SppPttController.cpp
)

# --- Find/Build All Dependencies FIRST ---

# 1. Find Qt6 - This MUST come before any qt_* commands.
find_package(Qt6 6.9 REQUIRED COMPONENTS Quick Network Multimedia Bluetooth)
qt_policy(SET QTP0002 NEW)
if(ANDROID)
    # The project builds both the main app and a dedicated Qt Android service binary.
    # Use per-target Android build directories so deployment artifacts do not collide.
    set(QT_USE_TARGET_ANDROID_BUILD_DIR ON CACHE BOOL
        "Use per-target Android build directories for Qt Android deployment" FORCE)

    # AndroidExtras is optional in Qt 6.5+ where APIs moved to QtCore
    find_package(Qt6AndroidExtras QUIET)
    # CorePrivate needed for QtAndroidPrivate permission APIs (qandroidextras_p.h)
    find_package(Qt6 COMPONENTS CorePrivate QUIET)

    # Add OpenSSL support via KDAB
       include(FetchContent)
       FetchContent_Declare(
           android_openssl
           DOWNLOAD_EXTRACT_TIMESTAMP true
           URL https://github.com/KDAB/android_openssl/archive/refs/heads/master.zip
       )
       FetchContent_MakeAvailable(android_openssl)
       include(${android_openssl_SOURCE_DIR}/android_openssl.cmake)

endif()

# 2. Find/Build Opus (Platform-Aware)
if(ANDROID)
    # --- ANDROID ---
    message(STATUS "Android build detected. Building Opus from 3rdparty/opus")
    set(OPUS_BUILD_TESTING OFF CACHE BOOL "Disable Opus tests" FORCE)
    set(OPUS_BUILD_DEMO OFF CACHE BOOL "Disable Opus demo" FORCE)
    set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "Disable Opus programs" FORCE)
