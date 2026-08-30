/*
 * Copyright (C) 2025 Silviu YO6SAY
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include "ReflectorClient.h"
#include "AppLaunchMode.h"
#include <QCoreApplication>
#include <QThread>
#include <QMetaObject>
#include <QDebug>
#include <QTime>
#include <QTimer>
#include <QSet>
#include <QVariantMap>
#include <QJsonArray>
#include <QJsonValue>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QNetworkRequest>
#include <QUrl>
#include <QLocale>
#include <algorithm>
#include <optional>

#if defined(Q_OS_ANDROID)
#  include <QtCore/private/qandroidextras_p.h>
#  include <QFuture>
#  include <QFutureWatcher>
#  include <unistd.h>
namespace AndroidReflectorClientJniInterop {
void drainPendingReflectorActions(ReflectorClient *client);
}
#endif

namespace {
const QString kAudioRouteSpeaker = QStringLiteral("speaker");
const QString kAudioRouteWiredHeadset = QStringLiteral("wired_headset");
const QString kAudioRouteBluetooth = QStringLiteral("bluetooth");

constexpr qreal kMinRxAudioLevelDb = 0.0;
constexpr qreal kMaxRxAudioLevelDb = 9.0;
constexpr qreal kMinTxAudioLevelDb = -12.0;
constexpr qreal kMaxTxAudioLevelDb = 12.0;
constexpr int kDefaultTgSelectTimeoutSeconds = 30;
constexpr int kMinTgSelectTimeoutSeconds = 1;
constexpr bool kDefaultTxTimeoutEnabled = true;
constexpr int kDefaultTxTimeoutSeconds = 175;
constexpr int kDefaultPttHangTimeMs = 100;
constexpr int kMaxPttHangTimeMs = 1000;
constexpr int kNoLearnedHardwarePttKeyCode = -1;
constexpr int kTxTimeoutWarningWindowSeconds = 10;
constexpr int kMaxTranscriptionChars = 1200;
constexpr int kAndroidSpeechErrorLanguageNotSupported = 12;
constexpr int kAndroidSpeechErrorLanguageUnavailable = 13;
constexpr int kTranscriptionSupportRefreshIntervalMs = 2000;
#if defined(Q_OS_ANDROID)
const QString kRecordAudioPermission = QStringLiteral("android.permission.RECORD_AUDIO");

QJniObject androidQtContext()
{
    return QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
}

std::optional<QtAndroidPrivate::PermissionResult> permissionResultFromFuture(
    const QFuture<QtAndroidPrivate::PermissionResult> &future,
    const char *operation)
{
    if (!future.isValid()) {
        qWarning() << operation << "returned an invalid permission future";
        return std::nullopt;
    }

    if (future.isCanceled()) {
        qWarning() << operation << "was canceled before Android returned a result";
        return std::nullopt;
    }

    if (future.resultCount() < 1) {
        qWarning() << operation << "finished without a permission result";
        return std::nullopt;
    }

    return future.resultAt(0);
}
#endif

QString normalizeAudioRouteId(const QString &routeId)
{
    const QString normalized = routeId.trimmed().toLower();
    if (normalized == kAudioRouteWiredHeadset || normalized == kAudioRouteBluetooth) {
        return normalized;
    }
    return kAudioRouteSpeaker;
}

qreal normalizeRxAudioLevelDb(qreal levelDb)
{
    return std::clamp(levelDb, kMinRxAudioLevelDb, kMaxRxAudioLevelDb);
}

qreal normalizeTxAudioLevelDb(qreal levelDb)
{
    return std::clamp(levelDb, kMinTxAudioLevelDb, kMaxTxAudioLevelDb);
}

qreal normalizeMeterLevel(qreal level)
{
    return std::clamp(level, 0.0, 1.0);
}

int normalizeTxTimeoutSeconds(int seconds)
{
    return seconds > 0 ? seconds : kDefaultTxTimeoutSeconds;
}

int normalizePttHangTimeMs(int milliseconds)
{
    if (milliseconds < 0) {
        return kDefaultPttHangTimeMs;
    }

    return std::min(milliseconds, kMaxPttHangTimeMs);
}

int normalizeTalkgroupSelectTimeoutSeconds(int seconds)
{
    return seconds >= kMinTgSelectTimeoutSeconds ? seconds : kDefaultTgSelectTimeoutSeconds;
}

QVariantMap describeAudioRoute(const QString &routeId)
{
    const QString normalized = normalizeAudioRouteId(routeId);
    if (normalized == kAudioRouteWiredHeadset) {
        return {
            {QStringLiteral("id"), normalized},
            {QStringLiteral("name"), QStringLiteral("Wired Headset")},
            {QStringLiteral("description"), QStringLiteral("Wired audio route")}
        };
    }

    if (normalized == kAudioRouteBluetooth) {
        return {
            {QStringLiteral("id"), normalized},
            {QStringLiteral("name"), QStringLiteral("Bluetooth")},
            {QStringLiteral("description"), QStringLiteral("Bluetooth voice route")}
        };
    }

    return {
        {QStringLiteral("id"), kAudioRouteSpeaker},
        {QStringLiteral("name"), QStringLiteral("Speaker")},
        {QStringLiteral("description"), QStringLiteral("Speaker + Internal mic")}
    };
}

QStringList normalizedAudioRouteIds(const QStringList &routeIds)
{
    QStringList normalized;
    for (const QString &routeId : routeIds) {
        const QString normalizedRoute = normalizeAudioRouteId(routeId);
        if (!normalized.contains(normalizedRoute)) {
            normalized.append(normalizedRoute);
        }
    }

    if (!normalized.contains(kAudioRouteSpeaker)) {
        normalized.append(kAudioRouteSpeaker);
    }

    QStringList ordered;
    if (normalized.contains(kAudioRouteSpeaker)) {
        ordered.append(kAudioRouteSpeaker);
    }
    if (normalized.contains(kAudioRouteWiredHeadset)) {
        ordered.append(kAudioRouteWiredHeadset);
    }
    if (normalized.contains(kAudioRouteBluetooth)) {
        ordered.append(kAudioRouteBluetooth);
    }

    return ordered;
}

QVariantList buildAudioRouteModel(const QStringList &routeIds)
{
    QVariantList routes;
    const QStringList ordered = normalizedAudioRouteIds(routeIds);
    routes.reserve(ordered.size());
    for (const QString &routeId : ordered) {
        routes.append(describeAudioRoute(routeId));
    }
    return routes;
}

QVariantMap describeNodeInfoEntry(const QString &key, const QString &value)
{
    return {
        {QStringLiteral("key"), key},
        {QStringLiteral("value"), value}
    };
}

QString trimTranscriptionTail(const QString &text)
{
    if (text.size() <= kMaxTranscriptionChars) {
        return text;
    }

    return text.right(kMaxTranscriptionChars).trimmed();
}

QStringList jsonStringList(const QJsonValue &value)
{
    QStringList strings;
    const QJsonArray array = value.toArray();
    strings.reserve(array.size());
    for (const QJsonValue &entry : array) {
        const QString text = entry.toString().trimmed();
        if (!text.isEmpty() && !strings.contains(text)) {
            strings.append(text);
        }
    }
    return strings;
}

QString displayLanguageName(const QString &languageTag)
{
    const QLocale locale(languageTag);
    QString languageName;
    if (locale.language() != QLocale::C) {
        languageName = QLocale::languageToString(locale.language());
    }
    if (languageName.isEmpty()) {
        languageName = languageTag;
    }

    QString territoryName;
    if (locale.territory() != QLocale::AnyTerritory) {
        territoryName = QLocale::territoryToString(locale.territory());
    }

    if (!territoryName.isEmpty()) {
        return QStringLiteral("%1 (%2)").arg(languageName, territoryName);
    }

    return languageName;
}

QVariantMap buildTranscriptionLanguageEntry(const QString &languageTag,
                                            bool installed,
                                            bool pending,
                                            bool activeDownload)
{
    QString status;
    if (installed) {
        status = QStringLiteral("Installed");
    } else if (pending || activeDownload) {
        status = QStringLiteral("Download in progress");
    } else {
        status = QStringLiteral("Available to download");
    }

    return {
        {QStringLiteral("tag"), languageTag},
        {QStringLiteral("name"), displayLanguageName(languageTag)},
        {QStringLiteral("status"), status},
        {QStringLiteral("installed"), installed},
        {QStringLiteral("pending"), pending},
        {QStringLiteral("activeDownload"), activeDownload}
    };
}
}

ReflectorClient* ReflectorClient::instance()
{
    // Ensure QCoreApplication exists before creating Qt objects
    QCoreApplication *app = QCoreApplication::instance();
    if (!app) {
        qWarning() << "ReflectorClient::instance() called before QCoreApplication created";
        return nullptr;
    }

    static ReflectorClient *client = nullptr;
    if (client) {
        return client;
    }

    if (QThread::currentThread() != app->thread()) {
        qCritical() << "ReflectorClient singleton must be created on the Qt application thread";
        return nullptr;
    }

    static ReflectorClient singleton;
    client = &singleton;
#if defined(Q_OS_ANDROID)
    AndroidReflectorClientJniInterop::drainPendingReflectorActions(client);
#endif
    return client;
}

ReflectorClient::ReflectorClient(QObject *parent) : QObject{parent},
    m_state(Disconnected),
    m_connectionStatus("Disconnected"),
    m_pttActive(false),
    m_txStopPending(false),
    m_audioReady(false),
    m_port(0),
    m_talkgroup(0),
    m_defaultTalkgroup(0),
    m_clientId(0),
    m_udpSequence(0),
    m_txSeconds(0),
    m_lastAudioSeq(0),
    m_currentTalker(""),
    m_currentTalkerName(""),
    m_isReceivingAudio(false)
{
    m_tcpSocket = new QTcpSocket(this);
    m_udpSocket = new QUdpSocket(this);
    m_heartbeatTimer = new QTimer(this);
    m_txTimer = new QTimer(this);
    m_pttHangTimer = new QTimer(this);
    m_connectTimer = new QTimer(this);
    m_reconnectTimer = new QTimer(this);
    m_protocolLivenessTimer = new QTimer(this);
    m_pttHangTimer->setSingleShot(true);
    m_connectTimer->setSingleShot(true);
    m_reconnectTimer->setSingleShot(true);
    m_protocolLivenessTimer->setSingleShot(true);
    m_audioTimeoutTimer = new QTimer(this);
    m_audioTimeoutTimer->setSingleShot(true);
    m_audioTimeoutTimer->setInterval(3000); // 3 second timeout
    m_transcriptionSupportRefreshTimer = new QTimer(this);
    m_transcriptionSupportRefreshTimer->setSingleShot(false);
    m_transcriptionSupportRefreshTimer->setInterval(kTranscriptionSupportRefreshIntervalMs);
    m_talkgroupSelectionTimer = new QTimer(this);
    m_talkgroupSelectionTimer->setInterval(1000);
    m_networkManager = new QNetworkAccessManager(this);

    connect(m_tcpSocket, &QTcpSocket::connected, this, &ReflectorClient::onTcpConnected);
    connect(m_tcpSocket, &QTcpSocket::disconnected, this, &ReflectorClient::onTcpDisconnected);
    connect(m_tcpSocket, &QTcpSocket::readyRead, this, &ReflectorClient::onTcpReadyRead);
    connect(m_udpSocket, &QUdpSocket::readyRead, this, &ReflectorClient::onUdpReadyRead);
    connect(m_heartbeatTimer, &QTimer::timeout, this, &ReflectorClient::onHeartbeatTimer);
    connect(m_txTimer, &QTimer::timeout, this, &ReflectorClient::onTxTimerTimeout);
    connect(m_pttHangTimer, &QTimer::timeout, this, &ReflectorClient::onPttHangTimerTimeout);
    connect(m_connectTimer, &QTimer::timeout, this, &ReflectorClient::onConnectTimeout);
    connect(m_reconnectTimer, &QTimer::timeout, this, &ReflectorClient::onReconnectBackoffTimeout);
    connect(m_protocolLivenessTimer, &QTimer::timeout, this, &ReflectorClient::onProtocolLivenessTimeout);
    connect(m_talkgroupSelectionTimer, &QTimer::timeout, this, &ReflectorClient::onTalkgroupSelectionTimer);
    connect(m_transcriptionSupportRefreshTimer, &QTimer::timeout,
            this, &ReflectorClient::refreshTranscriptionSupportState);
    connect(m_audioTimeoutTimer, &QTimer::timeout, this, [this]() {
        if (m_isReceivingAudio) {
            qDebug() << "Audio timeout - stopping receive indicator";
            setReceivingAudioState(false);
        }
    });
    connect(m_tcpSocket, &QTcpSocket::errorOccurred, this, &ReflectorClient::onTcpError);
    m_txTimer->setInterval(1000);
    m_txTimeoutEnabled = kDefaultTxTimeoutEnabled;
    m_txTimeoutSeconds = normalizeTxTimeoutSeconds(kDefaultTxTimeoutSeconds);
    m_pttHangTimeMs = normalizePttHangTimeMs(kDefaultPttHangTimeMs);

    // Initialize audio engine and thread
    initializeAudioEngine();

    m_availableAudioRoutes = buildAudioRouteModel(QStringList{kAudioRouteSpeaker});
    m_currentAudioRoute = kAudioRouteSpeaker;
    m_preferredAudioRoute = kAudioRouteSpeaker;

#if defined(Q_OS_ANDROID)
    refreshHardwarePttSettings();
#endif

    const bool androidServiceLaunch = isAndroidServiceLaunchMode(QCoreApplication::arguments());
    checkTranscriptionAvailability(androidServiceLaunch);

    connect(this, &ReflectorClient::activityPaused, this, [this]() {
#if defined(Q_OS_ANDROID)
        if (!m_transcriptionSessionActive) {
            return;
        }

        m_transcriptionSuspendedByPause = true;
        stopTranscriptionSession(false);
#endif
    });
    connect(this, &ReflectorClient::activityResumed, this, [this]() {
#if defined(Q_OS_ANDROID)
        const bool shouldResume = m_transcriptionSuspendedByPause
                && m_liveTranscriptionEnabled
                && m_isReceivingAudio;
        m_transcriptionSuspendedByPause = false;
        if (shouldResume) {
            startTranscriptionSession();
        }
#endif
    });

#if defined(Q_OS_ANDROID)
    QTimer::singleShot(0, this, [this, androidServiceLaunch]() {
        initializeAndroidAudioRouting();
        if (!androidServiceLaunch) {
            ensureVoipService();
            return;
        }

        qDebug() << "ReflectorClient running inside Android service launch mode";
    });
#endif

    if (!androidServiceLaunch) {
        // Ensure UI gets the initial state values after the QML engine is ready.
        QTimer::singleShot(100, this, [this]() {
            qDebug() << "Emitting initial signals:";
            qDebug() << "  connectionStatus:" << m_connectionStatus;
            qDebug() << "  pttActive:" << m_pttActive;
            qDebug() << "  currentTalker:" << m_currentTalker;
            qDebug() << "  currentTalkerName:" << m_currentTalkerName;
            qDebug() << "  txTimeString:" << txTimeString();
            qDebug() << "  audioReady:" << m_audioReady;
            qDebug() << "  isDisconnected:" << (m_state == Disconnected);

            emit connectionStatusChanged();
            emit pttActiveChanged();
            emit currentTalkerChanged();
            emit currentTalkerNameChanged();
            emit txTimeStringChanged();
            emit audioReadyChanged();
            emit availableAudioRoutesChanged();
            emit currentAudioRouteChanged();
            emit preferredAudioRouteChanged();
            emit rxAudioLevelDbChanged();
            emit txAudioLevelDbChanged();
            emit hardwarePttSettingsChanged();
            emit hardwarePttLearningActiveChanged();
            emit hardwarePttLearningResultChanged();
            emit rxMeterLevelChanged();
            emit rxMeterPeakLevelChanged();
            emit txMeterLevelChanged();
            emit txMeterPeakLevelChanged();
        });
    }

    // Run heavy cleanup while the event loop is still alive, before dlclose()
    // triggers static destruction with the Android main thread already blocked.
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit,
            this, &ReflectorClient::prepareForShutdown);
}

ReflectorClient::~ReflectorClient()
{
    if (!m_shutdownComplete) {
        // Fallback: prepareForShutdown() was not called (abnormal shutdown path).
        // This runs during static destruction / dlclose where the Qt event loop
        // and JNI environment may already be torn down, so only do the minimum:
        // join the audio thread with a bounded wait to avoid an infinite block.
        qWarning() << "ReflectorClient::~ReflectorClient - prepareForShutdown was not called,"
                       " performing fallback cleanup";
        if (m_audioThread && m_audioThread->isRunning()) {
            m_audioThread->quit();
            if (!m_audioThread->wait(2000))
                m_audioThread->terminate();
        }
    }
}

void ReflectorClient::prepareForShutdown()
{
    if (m_shutdownComplete)
        return;
    m_shutdownComplete = true;

    qInfo() << "ReflectorClient::prepareForShutdown - cleaning up while event loop is alive";

#if defined(Q_OS_ANDROID)
    // Mark transcription inactive without the BlockingQueuedConnection to the
    // audio thread — the thread is about to be terminated, so synchronously
    // closing the pipe fd is unnecessary and risks blocking for too long.
    m_transcriptionSessionActive = false;
    QJniObject::callStaticMethod<void>("yo6say/latry/LatryTranscriptionManager",
                                       "destroy",
                                       "()V");
#endif

    // Stop all timers to prevent new work from being scheduled.
    if (m_heartbeatTimer)
        m_heartbeatTimer->stop();
    if (m_txTimer) {
        m_txTimer->stop();
        m_txTimeoutWarningFeedbackSent = false;
        m_txSeconds = 0;
    }
    if (m_pttHangTimer)
        m_pttHangTimer->stop();
    if (m_connectTimer)
        m_connectTimer->stop();
    if (m_reconnectTimer)
        m_reconnectTimer->stop();
    if (m_protocolLivenessTimer)
        m_protocolLivenessTimer->stop();
    if (m_audioTimeoutTimer)
        m_audioTimeoutTimer->stop();
    if (m_talkgroupSelectionTimer)
        m_talkgroupSelectionTimer->stop();
    if (m_transcriptionSupportRefreshTimer)
        m_transcriptionSupportRefreshTimer->stop();

    // Abort pending network reply.
    if (m_nameReply) {
        m_nameReply->abort();
        m_nameReply->deleteLater();
        m_nameReply = nullptr;
    }

    auto abortPortalReply = [this](QNetworkReply *&reply) {
        if (!reply)
            return;

        QObject::disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
        reply = nullptr;
    };

    abortPortalReply(m_portalAccessReply);
    abortPortalReply(m_portalEnrollReply);
    abortPortalReply(m_portalAdminUsersReply);
    abortPortalReply(m_portalAdminGroupsReply);
    abortPortalReply(m_portalAdminSourcesReply);
    abortPortalReply(m_portalAdminTokensReply);
    abortPortalReply(m_portalAdminGroupOptionsReply);
    abortPortalReply(m_portalAdminUserSaveReply);
    abortPortalReply(m_portalAdminUserDeleteReply);
    abortPortalReply(m_portalAdminGroupSaveReply);
    abortPortalReply(m_portalAdminGroupDeleteReply);
    abortPortalReply(m_portalAdminSourceSaveReply);
    abortPortalReply(m_portalAdminSourceDeleteReply);
    abortPortalReply(m_portalAdminTokenRevokeReply);

    // Shut down the audio thread with a tight timeout. Background ANR threshold
    // on Android 14+ is ~5 s; keep the total prepareForShutdown() time well
    // under that. If the thread cannot exit in 500 ms it is stuck — terminate it.
    // Per Qt docs: "Use QThread::wait() after terminate(), to be sure."
    if (m_audioThread && m_audioThread->isRunning()) {
        m_audioThread->quit();
        if (!m_audioThread->wait(500)) {
            qWarning() << "ReflectorClient::prepareForShutdown - audio thread did not exit"
                           " within 500 ms, terminating";
            m_audioThread->terminate();
            m_audioThread->wait(200);
        }
    }

#if defined(Q_OS_ANDROID)
    stopAndroidAudioRouting();
    stopVoipService();
    clearConnectionState();
#endif

    qInfo() << "ReflectorClient::prepareForShutdown - cleanup complete";
}

// --- Property Getters ---

QString ReflectorClient::connectionStatus() const { return m_connectionStatus; }
bool ReflectorClient::pttActive() const { return m_pttActive; }
QString ReflectorClient::currentTalker() const { return m_currentTalker; }
QVariantList ReflectorClient::monitoredTalkgroupsModel() const
{
    QVariantList talkgroups;
    talkgroups.reserve(m_monitoredTalkgroups.size());
    for (quint32 talkgroup : m_monitoredTalkgroups) {
        talkgroups.append(talkgroup);
    }
    return talkgroups;
}

QVariantList ReflectorClient::nodeInfoReadOnlyEntries() const
{
    return {
        describeNodeInfoEntry(QStringLiteral("sw"), nodeInfoSoftwareName()),
        describeNodeInfoEntry(QStringLiteral("swVer"), nodeInfoSoftwareVersion()),
        describeNodeInfoEntry(QStringLiteral("tip"), nodeInfoTipHtml()),
        describeNodeInfoEntry(QStringLiteral("Website"), nodeInfoWebsite())
    };
}

void ReflectorClient::shutdownApplication()
{
    if (m_pttActive) {
        forcePttRelease();
    }

    disconnectFromServer();
    prepareForShutdown();

#if defined(Q_OS_ANDROID)
    QJniObject::callStaticMethod<void>(
        "yo6say/latry/LatryActivity",
        "requestFinishAndRemoveTask",
        "()V");
#endif

    QCoreApplication::quit();
}

bool ReflectorClient::voipBackgroundServiceRunning() const
{
#if defined(Q_OS_ANDROID)
    return QJniObject::callStaticMethod<jboolean>(
        "yo6say/latry/VoipBackgroundService",
        "isRunning",
        "()Z");
#else
    return false;
#endif
}

QString ReflectorClient::currentTalkerName() const
{
    return m_currentTalkerName;
}

QString ReflectorClient::txTimeString() const
{
    QTime t(0, 0);
    t = t.addSecs(m_txSeconds);
    if (t.hour() > 0)
        return t.toString("h:mm:ss");
    else
        return t.toString("mm:ss");
}

void ReflectorClient::onTxTimerTimeout()
{
    ++m_txSeconds;
    emit txTimeStringChanged();
    updateTxTimeoutWarningState();

    if (m_txTimeoutWarning && !m_txTimeoutWarningFeedbackSent) {
        m_txTimeoutWarningFeedbackSent = true;
#if defined(Q_OS_ANDROID)
        triggerTxTimeoutWarningHaptic();
#endif
    }

    if (!m_txTimeoutEnabled || !m_pttActive || m_txStopPending || m_txSeconds < m_txTimeoutSeconds) {
        return;
    }

    qWarning() << "TX timeout reached after" << m_txTimeoutSeconds
               << "seconds, releasing PTT";
    forcePttRelease();
}

void ReflectorClient::selectTalkgroup(quint32 talkgroup)
{
    selectTalkgroupInternal(talkgroup, TalkgroupSelectionOrigin::Manual);
}

void ReflectorClient::updateProfileConfiguration(quint32 defaultTalkgroup,
                                                 const QString &monitoredTalkgroups,
                                                 int tgSelectTimeoutSeconds)
{
    m_defaultTalkgroup = defaultTalkgroup;
    m_tgSelectTimeoutSeconds = normalizeTgSelectTimeoutSeconds(tgSelectTimeoutSeconds);
    applyMonitoredTalkgroups(monitoredTalkgroups);

    if (m_state == Connected) {
        sendTgMonitor(m_monitoredTalkgroups);
        if (m_talkgroup > 0) {
            resetTalkgroupSelectionTimer();
        } else {
            stopTalkgroupSelectionTimer();
        }
        refreshConnectionStatus();
#if defined(Q_OS_ANDROID)
        saveConnectionState();
#endif
    }
}

int ReflectorClient::normalizeTgSelectTimeoutSeconds(int seconds)
{
    return normalizeTalkgroupSelectTimeoutSeconds(seconds);
}

QString ReflectorClient::nodeInfoSoftwareName()
{
    return QStringLiteral("Latry");
}

QString ReflectorClient::nodeInfoSoftwareVersion()
{
    return QStringLiteral(LATRY_VERSION_NAME);
}

QString ReflectorClient::nodeInfoTipHtml()
{
    return QStringLiteral("I'm using <a href=\"https://latry.app\" target=\"_blank\">Latry.app</a>");
}

QString ReflectorClient::nodeInfoWebsite()
{
    return QStringLiteral("https://latry.app");
}

bool ReflectorClient::isReservedNodeInfoKey(const QString &key)
{
    static const QSet<QString> reservedKeys = {
        QStringLiteral("sw"),
        QStringLiteral("swver"),
        QStringLiteral("tip"),
        QStringLiteral("website"),
        QStringLiteral("callsign")
    };
    return reservedKeys.contains(key.trimmed().toLower());
}

QJsonObject ReflectorClient::sanitizeCustomNodeInfoEntries(const QVariantList &entries)
{
    QJsonObject normalizedEntries;

    for (const QVariant &entryVariant : entries) {
        const QVariantMap entry = entryVariant.toMap();
        const QString key = entry.value(QStringLiteral("key")).toString().trimmed();
        const QString value = entry.value(QStringLiteral("value")).toString().trimmed();
        if (key.isEmpty() || value.isEmpty() || isReservedNodeInfoKey(key)) {
            continue;
        }
        normalizedEntries.insert(key, QJsonValue(value));
    }

    return normalizedEntries;
}

void ReflectorClient::setCustomNodeInfoEntries(const QVariantList &entries)
{
    const QJsonObject sanitizedEntries = sanitizeCustomNodeInfoEntries(entries);
    if (m_customNodeInfoJson == sanitizedEntries) {
        return;
    }

    m_customNodeInfoJson = sanitizedEntries;

    if (m_state == Connected) {
        sendNodeInfo();
    }
}

void ReflectorClient::setPreferredAudioRoute(const QString &routeId)
{
    const QString normalizedRoute = normalizeAudioRouteId(routeId);
    if (m_preferredAudioRoute != normalizedRoute) {
        m_preferredAudioRoute = normalizedRoute;
        emit preferredAudioRouteChanged();
    }

#if defined(Q_OS_ANDROID)
    initializeAndroidAudioRouting();

    QJniObject context = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: Failed to get Android context for audio route selection";
        return;
    }

    const QJniObject routeString = QJniObject::fromString(normalizedRoute);
    QJniObject::callStaticMethod<void>(
        "yo6say/latry/LatryAudioRouteManager",
        "setPreferredRoute",
        "(Landroid/content/Context;Ljava/lang/String;)V",
        context.object(),
        routeString.object());
#else
    setAudioRouteState(normalizedRoute, QStringList{normalizedRoute});
#endif
}

void ReflectorClient::setRxAudioLevelDb(qreal levelDb)
{
    const qreal normalizedLevel = normalizeRxAudioLevelDb(levelDb);
    if (m_rxAudioLevelDb != normalizedLevel) {
        m_rxAudioLevelDb = normalizedLevel;
        emit rxAudioLevelDbChanged();
    }

    applyAudioLevelsToEngine();
}

void ReflectorClient::setTxAudioLevelDb(qreal levelDb)
{
    const qreal normalizedLevel = normalizeTxAudioLevelDb(levelDb);
    if (m_txAudioLevelDb != normalizedLevel) {
        m_txAudioLevelDb = normalizedLevel;
        emit txAudioLevelDbChanged();
    }

    applyAudioLevelsToEngine();
}

void ReflectorClient::setTxTimeoutSeconds(int seconds)
{
    const int normalizedSeconds = normalizeTxTimeoutSeconds(seconds);
    if (m_txTimeoutSeconds != normalizedSeconds) {
        m_txTimeoutSeconds = normalizedSeconds;
        emit txTimeoutSecondsChanged();
    }

    updateTxTimeoutWarningState();

    if (m_pttActive && !m_txStopPending && m_txSeconds >= m_txTimeoutSeconds) {
        forcePttRelease();
    }
}

void ReflectorClient::setPttHangTimeMs(int milliseconds)
{
    const int normalizedMilliseconds = normalizePttHangTimeMs(milliseconds);
    if (m_pttHangTimeMs == normalizedMilliseconds) {
        return;
    }

    m_pttHangTimeMs = normalizedMilliseconds;
    emit pttHangTimeMsChanged();

    if (m_pttReleasePending) {
        if (m_pttHangTimeMs == 0) {
            forcePttRelease();
        } else if (m_pttHangTimer) {
            m_pttHangTimer->start(m_pttHangTimeMs);
        }
    }
}


bool ReflectorClient::hasPortalToken() const
{
#if defined(Q_OS_ANDROID)
    const QJniObject context = androidQtContext();
    if (!context.isValid())
        return false;

    return QJniObject::callStaticMethod<jboolean>(
        "yo6say/latry/LatryPortalTokenStore",
        "hasToken",
        "(Landroid/content/Context;)Z",
        context.object());
#else
    return false;
#endif
}

bool ReflectorClient::savePortalToken(const QString &token)
{
#if defined(Q_OS_ANDROID)
    const QJniObject context = androidQtContext();
    if (!context.isValid())
        return false;

    const QJniObject tokenObject =
        QJniObject::fromString(token.trimmed());

    const bool saved =
        QJniObject::callStaticMethod<jboolean>(
            "yo6say/latry/LatryPortalTokenStore",
            "saveToken",
            "(Landroid/content/Context;Ljava/lang/String;)Z",
            context.object(),
            tokenObject.object<jstring>());

    if (saved)
        refreshPortalAccess();

    return saved;
#else
    Q_UNUSED(token);
    return false;
#endif
}

void ReflectorClient::clearPortalToken()
{
#if defined(Q_OS_ANDROID)
    const QJniObject context = androidQtContext();

    if (context.isValid()) {
        QJniObject::callStaticMethod<void>(
            "yo6say/latry/LatryPortalTokenStore",
            "clearToken",
            "(Landroid/content/Context;)V",
            context.object());
    }

    auto abortPortalReply = [this](QNetworkReply *&reply) {
        if (!reply)
            return;

        QObject::disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
        reply = nullptr;
    };

    abortPortalReply(m_portalAccessReply);
    abortPortalReply(m_portalEnrollReply);
    abortPortalReply(m_portalAdminUsersReply);
    abortPortalReply(m_portalAdminGroupsReply);
    abortPortalReply(m_portalAdminSourcesReply);
    abortPortalReply(m_portalAdminTokensReply);
    abortPortalReply(m_portalAdminGroupOptionsReply);
    abortPortalReply(m_portalAdminUserSaveReply);
    abortPortalReply(m_portalAdminUserDeleteReply);
    abortPortalReply(m_portalAdminGroupSaveReply);
    abortPortalReply(m_portalAdminGroupDeleteReply);
    abortPortalReply(m_portalAdminSourceSaveReply);
    abortPortalReply(m_portalAdminSourceDeleteReply);
    abortPortalReply(m_portalAdminTokenRevokeReply);

    m_portalAccessLoading = false;
    m_hasAdminAccess = false;
    m_portalCapabilities.clear();

    m_portalAdminUsers.clear();
    m_portalAdminGroups.clear();
    m_portalAdminSources.clear();
    m_portalAdminTokens.clear();
    m_portalAdminGroupSources.clear();
    m_portalAdminGroupCapabilities.clear();

    emit portalAccessChanged();
    emit portalAdminUsersChanged();
    emit portalAdminGroupsChanged();
    emit portalAdminSourcesChanged();
    emit portalAdminTokensChanged();
    emit portalAdminGroupOptionsChanged();
#endif
}


void ReflectorClient::refreshPortalAdminUsers()
{
#if defined(Q_OS_ANDROID)
    m_portalAdminUsers.clear();

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_USER_MANAGE"))) {
        emit portalAdminUsersChanged();
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminUsersChanged();
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminUsersChanged();
        return;
    }

    if (m_portalAdminUsersReply) {
        m_portalAdminUsersReply->abort();
        m_portalAdminUsersReply->deleteLater();
        m_portalAdminUsersReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_users.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->get(request);
    m_portalAdminUsersReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminUsersReply == reply)
                m_portalAdminUsersReply = nullptr;

            m_portalAdminUsers.clear();

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {

                const QJsonDocument document =
                    QJsonDocument::fromJson(data);

                if (document.isObject()) {

                    const QJsonArray users =
                        document.object()
                            .value(QStringLiteral("users"))
                            .toArray();

                    for (const QJsonValue &value : users) {
                        if (!value.isObject())
                            continue;

                        const QJsonObject user = value.toObject();

                        QVariantMap item;
                        item.insert(
                            QStringLiteral("id"),
                            user.value(QStringLiteral("id")).toInt()
                        );
                        item.insert(
                            QStringLiteral("callsign"),
                            user.value(QStringLiteral("callsign")).toString()
                        );
                        item.insert(
                            QStringLiteral("enabled"),
                            user.value(QStringLiteral("enabled")).toBool()
                        );
                        item.insert(
                            QStringLiteral("active_tokens"),
                            user.value(QStringLiteral("active_tokens")).toInt()
                        );

                        QStringList groups;
                        const QJsonArray groupArray =
                            user.value(QStringLiteral("groups")).toArray();

                        for (const QJsonValue &group : groupArray)
                            groups.append(group.toString());

                        item.insert(
                            QStringLiteral("groups"),
                            groups
                        );

                        m_portalAdminUsers.append(item);
                    }
                }

            } else {
                qWarning()
                    << "Latry admin users request failed:"
                    << reply->attribute(
                           QNetworkRequest::HttpStatusCodeAttribute
                       ).toInt();
            }

            reply->deleteLater();
            emit portalAdminUsersChanged();
        }
    );

#else
    m_portalAdminUsers.clear();
    emit portalAdminUsersChanged();
#endif
}


void ReflectorClient::refreshPortalAdminGroups()
{
#if defined(Q_OS_ANDROID)
    m_portalAdminGroups.clear();

    const bool allowed =
        m_portalCapabilities.contains(QStringLiteral("APP_GROUP_MANAGE")) ||
        m_portalCapabilities.contains(QStringLiteral("APP_USER_MANAGE"));

    if (!allowed) {
        emit portalAdminGroupsChanged();
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminGroupsChanged();
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminGroupsChanged();
        return;
    }

    if (m_portalAdminGroupsReply) {
        m_portalAdminGroupsReply->abort();
        m_portalAdminGroupsReply->deleteLater();
        m_portalAdminGroupsReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_groups.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->get(request);
    m_portalAdminGroupsReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminGroupsReply == reply)
                m_portalAdminGroupsReply = nullptr;

            m_portalAdminGroups.clear();

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {

                const QJsonDocument document =
                    QJsonDocument::fromJson(data);

                if (document.isObject()) {

                    const QJsonArray groups =
                        document.object()
                            .value(QStringLiteral("groups"))
                            .toArray();

                    for (const QJsonValue &value : groups) {
                        if (!value.isObject())
                            continue;

                        const QJsonObject group = value.toObject();

                        QVariantMap item;
                        item.insert(
                            QStringLiteral("id"),
                            group.value(QStringLiteral("id")).toInt()
                        );
                        item.insert(
                            QStringLiteral("code"),
                            group.value(QStringLiteral("code")).toString()
                        );
                        item.insert(
                            QStringLiteral("name"),
                            group.value(QStringLiteral("name")).toString()
                        );
                        item.insert(
                            QStringLiteral("enabled"),
                            group.value(QStringLiteral("enabled")).toBool()
                        );
                        item.insert(
                            QStringLiteral("members"),
                            group.value(QStringLiteral("members")).toInt()
                        );

                        QStringList sources;
                        const QJsonArray sourceArray =
                            group.value(QStringLiteral("sources")).toArray();

                        for (const QJsonValue &source : sourceArray)
                            sources.append(source.toString());

                        item.insert(
                            QStringLiteral("sources"),
                            sources
                        );

                        QStringList capabilities;
                        const QJsonArray capabilityArray =
                            group.value(QStringLiteral("capabilities")).toArray();

                        for (const QJsonValue &capability : capabilityArray)
                            capabilities.append(capability.toString());

                        item.insert(
                            QStringLiteral("capabilities"),
                            capabilities
                        );

                        m_portalAdminGroups.append(item);
                    }
                }

            } else {
                qWarning()
                    << "Latry admin groups request failed:"
                    << reply->attribute(
                           QNetworkRequest::HttpStatusCodeAttribute
                       ).toInt();
            }

            reply->deleteLater();
            emit portalAdminGroupsChanged();
        }
    );

#else
    m_portalAdminGroups.clear();
    emit portalAdminGroupsChanged();
#endif
}




void ReflectorClient::refreshPortalAdminSources()
{
#if defined(Q_OS_ANDROID)
    m_portalAdminSources.clear();

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_SOURCE_MANAGE"))) {
        emit portalAdminSourcesChanged();
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminSourcesChanged();
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminSourcesChanged();
        return;
    }

    if (m_portalAdminSourcesReply) {
        m_portalAdminSourcesReply->abort();
        m_portalAdminSourcesReply->deleteLater();
        m_portalAdminSourcesReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_sources.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->get(request);
    m_portalAdminSourcesReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminSourcesReply == reply)
                m_portalAdminSourcesReply = nullptr;

            m_portalAdminSources.clear();

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {

                const QJsonDocument document =
                    QJsonDocument::fromJson(data);

                if (document.isObject()) {

                    const QJsonArray sources =
                        document.object()
                            .value(QStringLiteral("sources"))
                            .toArray();

                    for (const QJsonValue &value : sources) {
                        if (!value.isObject())
                            continue;

                        const QJsonObject source = value.toObject();

                        QVariantMap item;

                        item.insert(
                            QStringLiteral("id"),
                            source.value(QStringLiteral("id")).toInt()
                        );
                        item.insert(
                            QStringLiteral("code"),
                            source.value(QStringLiteral("code")).toString()
                        );
                        item.insert(
                            QStringLiteral("name"),
                            source.value(QStringLiteral("name")).toString()
                        );
                        item.insert(
                            QStringLiteral("type"),
                            source.value(QStringLiteral("type")).toString()
                        );
                        item.insert(
                            QStringLiteral("endpoint"),
                            source.value(QStringLiteral("endpoint")).toString()
                        );
                        item.insert(
                            QStringLiteral("enabled"),
                            source.value(QStringLiteral("enabled")).toBool()
                        );
                        item.insert(
                            QStringLiteral("sort_order"),
                            source.value(QStringLiteral("sort_order")).toInt()
                        );
                        item.insert(
                            QStringLiteral("group_count"),
                            source.value(QStringLiteral("group_count")).toInt()
                        );

                        m_portalAdminSources.append(item);
                    }
                }

            } else {
                qWarning()
                    << "Latry admin sources request failed:"
                    << reply->attribute(
                           QNetworkRequest::HttpStatusCodeAttribute
                       ).toInt();
            }

            reply->deleteLater();
            emit portalAdminSourcesChanged();
        }
    );

#else
    m_portalAdminSources.clear();
    emit portalAdminSourcesChanged();
#endif
}


void ReflectorClient::savePortalAdminSource(
    const QString &code,
    const QString &name,
    const QString &type,
    const QString &endpoint,
    bool enabled,
    int sortOrder)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_SOURCE_MANAGE"))) {
        emit portalAdminSourceSaveFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminSourceSaveFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminSourceSaveFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminSourceSaveReply) {
        m_portalAdminSourceSaveReply->abort();
        m_portalAdminSourceSaveReply->deleteLater();
        m_portalAdminSourceSaveReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("code"), code.trimmed().toUpper());
    payload.insert(QStringLiteral("name"), name.trimmed());
    payload.insert(QStringLiteral("type"), type.trimmed().toLower());
    payload.insert(QStringLiteral("endpoint"), endpoint.trimmed());
    payload.insert(QStringLiteral("enabled"), enabled);
    payload.insert(QStringLiteral("sort_order"), sortOrder);

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_source_save.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminSourceSaveReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminSourceSaveReply == reply)
                m_portalAdminSourceSaveReply = nullptr;

            const QByteArray data = reply->readAll();
            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            bool success = false;
            QString message;

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral("Vir je shranjen.");

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral("Shranjevanje vira ni uspelo.");
            }

            reply->deleteLater();

            if (success) {
                refreshPortalAdminSources();
                refreshPortalAdminGroups();
            }

            emit portalAdminSourceSaveFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(code)
    Q_UNUSED(name)
    Q_UNUSED(type)
    Q_UNUSED(endpoint)
    Q_UNUSED(enabled)
    Q_UNUSED(sortOrder)

    emit portalAdminSourceSaveFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}


void ReflectorClient::deletePortalAdminSource(
    const QString &code)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_SOURCE_MANAGE"))) {
        emit portalAdminSourceDeleteFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminSourceDeleteFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminSourceDeleteFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminSourceDeleteReply) {
        m_portalAdminSourceDeleteReply->abort();
        m_portalAdminSourceDeleteReply->deleteLater();
        m_portalAdminSourceDeleteReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(
        QStringLiteral("code"),
        code.trimmed().toUpper()
    );

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_source_delete.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminSourceDeleteReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminSourceDeleteReply == reply)
                m_portalAdminSourceDeleteReply = nullptr;

            const QByteArray data = reply->readAll();
            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            bool success = false;
            QString message;

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral("Vir je preklican.");

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral("Preklic vira ni uspel.");
            }

            reply->deleteLater();

            if (success) {
                refreshPortalAdminSources();
                refreshPortalAdminGroups();
                refreshPortalAdminGroupOptions();
            }

            emit portalAdminSourceDeleteFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(code)

    emit portalAdminSourceDeleteFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}


void ReflectorClient::refreshPortalAdminTokens()
{
#if defined(Q_OS_ANDROID)
    m_portalAdminTokens.clear();

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_TOKEN_MANAGE"))) {
        emit portalAdminTokensChanged();
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminTokensChanged();
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminTokensChanged();
        return;
    }

    if (m_portalAdminTokensReply) {
        m_portalAdminTokensReply->abort();
        m_portalAdminTokensReply->deleteLater();
        m_portalAdminTokensReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_tokens.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->get(request);
    m_portalAdminTokensReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminTokensReply == reply)
                m_portalAdminTokensReply = nullptr;

            m_portalAdminTokens.clear();

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {

                const QJsonDocument document =
                    QJsonDocument::fromJson(data);

                if (document.isObject()) {

                    const QJsonArray tokens =
                        document.object()
                            .value(QStringLiteral("tokens"))
                            .toArray();

                    for (const QJsonValue &value : tokens) {
                        if (!value.isObject())
                            continue;

                        const QJsonObject token = value.toObject();

                        QVariantMap item;

                        item.insert(
                            QStringLiteral("id"),
                            token.value(QStringLiteral("id")).toInt()
                        );
                        item.insert(
                            QStringLiteral("callsign"),
                            token.value(QStringLiteral("callsign")).toString()
                        );
                        item.insert(
                            QStringLiteral("label"),
                            token.value(QStringLiteral("label")).toString()
                        );
                        item.insert(
                            QStringLiteral("device_id"),
                            token.value(QStringLiteral("device_id")).toString()
                        );
                        item.insert(
                            QStringLiteral("current_token"),
                            token.value(QStringLiteral("current_token")).toBool()
                        );
                        item.insert(
                            QStringLiteral("created_at"),
                            token.value(QStringLiteral("created_at")).toString()
                        );
                        item.insert(
                            QStringLiteral("last_used_at"),
                            token.value(QStringLiteral("last_used_at")).toString()
                        );
                        item.insert(
                            QStringLiteral("expires_at"),
                            token.value(QStringLiteral("expires_at")).toString()
                        );

                        m_portalAdminTokens.append(item);
                    }
                }

            } else {
                qWarning()
                    << "Latry admin devices request failed:"
                    << reply->attribute(
                           QNetworkRequest::HttpStatusCodeAttribute
                       ).toInt();
            }

            reply->deleteLater();
            emit portalAdminTokensChanged();
        }
    );

#else
    m_portalAdminTokens.clear();
    emit portalAdminTokensChanged();
#endif
}


void ReflectorClient::revokePortalAdminToken(int tokenId)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_TOKEN_MANAGE"))) {
        emit portalAdminTokenRevokeFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    if (tokenId <= 0) {
        emit portalAdminTokenRevokeFinished(
            false,
            QStringLiteral("Invalid token")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminTokenRevokeFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminTokenRevokeFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminTokenRevokeReply) {
        m_portalAdminTokenRevokeReply->abort();
        m_portalAdminTokenRevokeReply->deleteLater();
        m_portalAdminTokenRevokeReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(
        QStringLiteral("token_id"),
        tokenId
    );

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_token_revoke.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminTokenRevokeReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminTokenRevokeReply == reply)
                m_portalAdminTokenRevokeReply = nullptr;

            const QByteArray data = reply->readAll();
            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            bool success = false;
            QString message;

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral(
                    "Dostop naprave je preklican."
                );

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral(
                        "Preklic naprave ni uspel."
                    );
            }

            reply->deleteLater();

            if (success)
                refreshPortalAdminTokens();

            emit portalAdminTokenRevokeFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(tokenId)

    emit portalAdminTokenRevokeFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}

void ReflectorClient::refreshPortalAdminGroupOptions()
{
#if defined(Q_OS_ANDROID)
    m_portalAdminGroupSources.clear();
    m_portalAdminGroupCapabilities.clear();

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_GROUP_MANAGE"))) {
        emit portalAdminGroupOptionsChanged();
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminGroupOptionsChanged();
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminGroupOptionsChanged();
        return;
    }

    if (m_portalAdminGroupOptionsReply) {
        m_portalAdminGroupOptionsReply->abort();
        m_portalAdminGroupOptionsReply->deleteLater();
        m_portalAdminGroupOptionsReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_group_options.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->get(request);
    m_portalAdminGroupOptionsReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminGroupOptionsReply == reply)
                m_portalAdminGroupOptionsReply = nullptr;

            m_portalAdminGroupSources.clear();
            m_portalAdminGroupCapabilities.clear();

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {

                const QJsonDocument document =
                    QJsonDocument::fromJson(data);

                if (document.isObject()) {

                    const QJsonObject root = document.object();

                    const QJsonArray sources =
                        root.value(QStringLiteral("sources")).toArray();

                    for (const QJsonValue &value : sources) {
                        if (!value.isObject())
                            continue;

                        const QJsonObject source = value.toObject();

                        QVariantMap item;
                        item.insert(
                            QStringLiteral("code"),
                            source.value(QStringLiteral("code")).toString()
                        );
                        item.insert(
                            QStringLiteral("name"),
                            source.value(QStringLiteral("name")).toString()
                        );
                        item.insert(
                            QStringLiteral("type"),
                            source.value(QStringLiteral("type")).toString()
                        );

                        m_portalAdminGroupSources.append(item);
                    }

                    const QJsonArray capabilities =
                        root.value(QStringLiteral("capabilities")).toArray();

                    for (const QJsonValue &value : capabilities) {
                        if (!value.isObject())
                            continue;

                        const QJsonObject capability = value.toObject();

                        QVariantMap item;
                        item.insert(
                            QStringLiteral("code"),
                            capability.value(QStringLiteral("code")).toString()
                        );
                        item.insert(
                            QStringLiteral("name"),
                            capability.value(QStringLiteral("name")).toString()
                        );

                        m_portalAdminGroupCapabilities.append(item);
                    }
                }

            } else {
                qWarning()
                    << "Latry admin group options request failed:"
                    << reply->attribute(
                           QNetworkRequest::HttpStatusCodeAttribute
                       ).toInt();
            }

            reply->deleteLater();
            emit portalAdminGroupOptionsChanged();
        }
    );

#else
    m_portalAdminGroupSources.clear();
    m_portalAdminGroupCapabilities.clear();
    emit portalAdminGroupOptionsChanged();
#endif
}


void ReflectorClient::savePortalAdminGroup(
    const QString &code,
    const QString &name,
    bool enabled,
    const QStringList &sources,
    const QStringList &capabilities)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_GROUP_MANAGE"))) {
        emit portalAdminGroupSaveFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminGroupSaveFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminGroupSaveFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminGroupSaveReply) {
        m_portalAdminGroupSaveReply->abort();
        m_portalAdminGroupSaveReply->deleteLater();
        m_portalAdminGroupSaveReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(
        QStringLiteral("code"),
        code.trimmed().toUpper()
    );
    payload.insert(
        QStringLiteral("name"),
        name.trimmed()
    );
    payload.insert(
        QStringLiteral("enabled"),
        enabled
    );

    QJsonArray sourceArray;
    for (const QString &source : sources)
        sourceArray.append(source);
    payload.insert(QStringLiteral("sources"), sourceArray);

    QJsonArray capabilityArray;
    for (const QString &capability : capabilities)
        capabilityArray.append(capability);
    payload.insert(QStringLiteral("capabilities"), capabilityArray);

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_group_save.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminGroupSaveReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminGroupSaveReply == reply)
                m_portalAdminGroupSaveReply = nullptr;

            const QByteArray data = reply->readAll();
            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            bool success = false;
            QString message;

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral("Skupina je shranjena.");

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral("Shranjevanje skupine ni uspelo.");
            }

            reply->deleteLater();

            if (success)
                refreshPortalAdminGroups();

            emit portalAdminGroupSaveFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(code)
    Q_UNUSED(name)
    Q_UNUSED(enabled)
    Q_UNUSED(sources)
    Q_UNUSED(capabilities)

    emit portalAdminGroupSaveFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}


void ReflectorClient::deletePortalAdminGroup(
    const QString &code)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_GROUP_MANAGE"))) {
        emit portalAdminGroupDeleteFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminGroupDeleteFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminGroupDeleteFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminGroupDeleteReply) {
        m_portalAdminGroupDeleteReply->abort();
        m_portalAdminGroupDeleteReply->deleteLater();
        m_portalAdminGroupDeleteReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(
        QStringLiteral("code"),
        code.trimmed().toUpper()
    );

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_group_delete.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminGroupDeleteReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminGroupDeleteReply == reply)
                m_portalAdminGroupDeleteReply = nullptr;

            const QByteArray data = reply->readAll();
            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            bool success = false;
            QString message;

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral("Skupina je preklicana.");

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral("Preklic skupine ni uspel.");
            }

            reply->deleteLater();

            if (success)
                refreshPortalAdminGroups();

            emit portalAdminGroupDeleteFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(code)

    emit portalAdminGroupDeleteFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}

void ReflectorClient::savePortalAdminUser(
    const QString &callsign,
    bool enabled,
    const QStringList &groups)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_USER_MANAGE"))) {
        emit portalAdminUserSaveFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminUserSaveFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminUserSaveFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminUserSaveReply) {
        m_portalAdminUserSaveReply->abort();
        m_portalAdminUserSaveReply->deleteLater();
        m_portalAdminUserSaveReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(
        QStringLiteral("callsign"),
        callsign.trimmed().toUpper()
    );
    payload.insert(
        QStringLiteral("enabled"),
        enabled
    );

    QJsonArray groupArray;
    for (const QString &group : groups)
        groupArray.append(group);

    payload.insert(
        QStringLiteral("groups"),
        groupArray
    );

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_user_save.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminUserSaveReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminUserSaveReply == reply)
                m_portalAdminUserSaveReply = nullptr;

            const QByteArray data = reply->readAll();
            bool success = false;
            QString message;

            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral("Uporabnik je shranjen.");

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral("Shranjevanje ni uspelo.");
            }

            reply->deleteLater();

            if (success)
                refreshPortalAdminUsers();

            emit portalAdminUserSaveFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(callsign)
    Q_UNUSED(enabled)
    Q_UNUSED(groups)

    emit portalAdminUserSaveFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}


void ReflectorClient::deletePortalAdminUser(
    const QString &callsign)
{
#if defined(Q_OS_ANDROID)

    if (!m_portalCapabilities.contains(
            QStringLiteral("APP_USER_MANAGE"))) {
        emit portalAdminUserDeleteFinished(
            false,
            QStringLiteral("Permission denied")
        );
        return;
    }

    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        emit portalAdminUserDeleteFinished(
            false,
            QStringLiteral("Android context unavailable")
        );
        return;
    }

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        emit portalAdminUserDeleteFinished(
            false,
            QStringLiteral("Portal token unavailable")
        );
        return;
    }

    if (m_portalAdminUserDeleteReply) {
        m_portalAdminUserDeleteReply->abort();
        m_portalAdminUserDeleteReply->deleteLater();
        m_portalAdminUserDeleteReply = nullptr;
    }

    QJsonObject payload;
    payload.insert(
        QStringLiteral("callsign"),
        callsign.trimmed().toUpper()
    );

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_admin_user_delete.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );
    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );
    request.setRawHeader("Accept", "application/json");

    QNetworkReply *reply = m_networkManager->post(
        request,
        QJsonDocument(payload).toJson(QJsonDocument::Compact)
    );

    m_portalAdminUserDeleteReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAdminUserDeleteReply == reply)
                m_portalAdminUserDeleteReply = nullptr;

            const QByteArray data = reply->readAll();
            const QJsonDocument document =
                QJsonDocument::fromJson(data);

            bool success = false;
            QString message;

            if (reply->error() == QNetworkReply::NoError &&
                document.isObject() &&
                document.object()
                    .value(QStringLiteral("ok"))
                    .toBool()) {

                success = true;
                message = QStringLiteral(
                    "Uporabnik je preklican."
                );

            } else {

                if (document.isObject()) {
                    message = document.object()
                                  .value(QStringLiteral("error"))
                                  .toString();
                }

                if (message.isEmpty())
                    message = QStringLiteral(
                        "Preklic uporabnika ni uspel."
                    );
            }

            reply->deleteLater();

            if (success)
                refreshPortalAdminUsers();

            emit portalAdminUserDeleteFinished(
                success,
                message
            );
        }
    );

#else
    Q_UNUSED(callsign)

    emit portalAdminUserDeleteFinished(
        false,
        QStringLiteral("Unsupported platform")
    );
#endif
}

void ReflectorClient::ensurePortalAccess(const QString &callsign,
                                         const QString &authKey)
{
#if defined(Q_OS_ANDROID)
    const QString normalizedCallsign = callsign.trimmed().toUpper();
    const QString normalizedAuthKey = authKey.trimmed();

    const QJniObject context = androidQtContext();
    if (!context.isValid())
        return;

    const QJniObject callsignObject =
        QJniObject::fromString(normalizedCallsign);

    const bool hasMatchingToken =
        QJniObject::callStaticMethod<jboolean>(
            "yo6say/latry/LatryPortalTokenStore",
            "hasTokenForCallsign",
            "(Landroid/content/Context;Ljava/lang/String;)Z",
            context.object(),
            callsignObject.object<jstring>());

    if (hasMatchingToken) {
        refreshPortalAccess();
        return;
    }

    /*
     * Stored token belongs to another callsign.
     * Remove it before enrolling the newly selected profile.
     */
    if (hasPortalToken())
        clearPortalToken();

    if (normalizedCallsign.isEmpty() || normalizedAuthKey.isEmpty())
        return;

    const QJniObject deviceIdObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "getOrCreateDeviceId",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString deviceId = deviceIdObject.toString().trimmed();

    if (deviceId.isEmpty())
        return;

    if (m_portalEnrollReply) {
        QObject::disconnect(
            m_portalEnrollReply,
            nullptr,
            this,
            nullptr
        );
        m_portalEnrollReply->abort();
        m_portalEnrollReply->deleteLater();
        m_portalEnrollReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_enroll.php"
        ))
    );

    request.setHeader(
        QNetworkRequest::ContentTypeHeader,
        QStringLiteral("application/json")
    );

    request.setRawHeader("Accept", "application/json");

    QJsonObject payload;
    payload.insert(QStringLiteral("callsign"), normalizedCallsign);
    payload.insert(QStringLiteral("auth_key"), normalizedAuthKey);
    payload.insert(QStringLiteral("device_id"), deviceId);
    payload.insert(QStringLiteral("label"), QStringLiteral("Latry Android"));

    const QByteArray body =
        QJsonDocument(payload).toJson(QJsonDocument::Compact);

    QNetworkReply *reply =
        m_networkManager->post(request, body);

    m_portalEnrollReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply, normalizedCallsign]() {

            if (m_portalEnrollReply == reply)
                m_portalEnrollReply = nullptr;

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {
                const QJsonDocument document =
                    QJsonDocument::fromJson(data);

                if (document.isObject()) {
                    const QString token =
                        document.object()
                            .value(QStringLiteral("token"))
                            .toString()
                            .trimmed();

                    if (!token.isEmpty()) {
                        const QJniObject context = androidQtContext();

                        if (context.isValid()) {
                            const QJniObject callsignObject =
                                QJniObject::fromString(normalizedCallsign);

                            const QJniObject tokenObject =
                                QJniObject::fromString(token);

                            const bool saved =
                                QJniObject::callStaticMethod<jboolean>(
                                    "yo6say/latry/LatryPortalTokenStore",
                                    "saveTokenForCallsign",
                                    "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Z",
                                    context.object(),
                                    callsignObject.object<jstring>(),
                                    tokenObject.object<jstring>());

                            if (saved)
                                refreshPortalAccess();
                        }
                    }
                }
            } else {
                qWarning()
                    << "Latry portal enrollment failed:"
                    << reply->attribute(
                           QNetworkRequest::HttpStatusCodeAttribute
                       ).toInt();
            }

            reply->deleteLater();
        }
    );
#else
    Q_UNUSED(callsign);
    Q_UNUSED(authKey);
#endif
}

void ReflectorClient::refreshPortalAccess()
{
#if defined(Q_OS_ANDROID)
    if (!m_networkManager)
        return;

    const QJniObject context = androidQtContext();
    if (!context.isValid())
        return;

    const QJniObject tokenObject =
        QJniObject::callStaticObjectMethod(
            "yo6say/latry/LatryPortalTokenStore",
            "loadToken",
            "(Landroid/content/Context;)Ljava/lang/String;",
            context.object());

    const QString token = tokenObject.toString().trimmed();

    if (token.isEmpty()) {
        m_portalAccessLoading = false;
        m_hasAdminAccess = false;
        m_portalCapabilities.clear();
        emit portalAccessChanged();
        return;
    }

    if (m_portalAccessReply) {
        QObject::disconnect(
            m_portalAccessReply,
            nullptr,
            this,
            nullptr
        );
        m_portalAccessReply->abort();
        m_portalAccessReply->deleteLater();
        m_portalAccessReply = nullptr;
    }

    QNetworkRequest request(
        QUrl(QStringLiteral(
            "https://svxportal.pmr446.si/latry_access.php"
        ))
    );

    request.setRawHeader(
        "Authorization",
        QByteArray("Bearer ") + token.toUtf8()
    );

    request.setRawHeader(
        "Accept",
        "application/json"
    );

    m_portalAccessLoading = true;
    emit portalAccessChanged();

    QNetworkReply *reply =
        m_networkManager->get(request);

    m_portalAccessReply = reply;

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {

            if (m_portalAccessReply == reply)
                m_portalAccessReply = nullptr;

            m_portalAccessLoading = false;
            m_hasAdminAccess = false;
            m_portalCapabilities.clear();

            if (!reply) {
                emit portalAccessChanged();
                return;
            }

            const QByteArray data = reply->readAll();

            if (reply->error() == QNetworkReply::NoError) {

                QJsonParseError parseError;

                const QJsonDocument document =
                    QJsonDocument::fromJson(
                        data,
                        &parseError
                    );

                if (parseError.error ==
                        QJsonParseError::NoError
                        && document.isObject()) {

                    const QJsonArray capabilities =
                        document.object()
                            .value(QStringLiteral(
                                "capabilities"
                            ))
                            .toArray();

                    for (const QJsonValue &value :
                         capabilities) {

                        const QString capability =
                            value.toString().trimmed();

                        if (capability.isEmpty())
                            continue;

                        m_portalCapabilities.append(
                            capability
                        );

                        if (capability.startsWith(
                                QStringLiteral("APP_"))
                            && capability.endsWith(
                                QStringLiteral("_MANAGE"))) {

                            m_hasAdminAccess = true;
                        }
                    }
                }

            } else {
                qWarning()
                    << "Latry portal access request failed:"
                    << reply->errorString();
            }

            reply->deleteLater();

            emit portalAccessChanged();
        }
    );

#else
    m_portalAccessLoading = false;
    m_hasAdminAccess = false;
    m_portalCapabilities.clear();
    emit portalAccessChanged();
#endif
}

void ReflectorClient::setHardwarePttEnabled(bool enabled)
{
    if (m_hardwarePttEnabled == enabled) {
        return;
    }

    m_hardwarePttEnabled = enabled;
    emit hardwarePttSettingsChanged();

#if defined(Q_OS_ANDROID)
    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: Failed to get Android context for hardware PTT settings";
        return;
    }

    QJniObject::callStaticMethod<void>(
        "yo6say/latry/HardwarePttSettingsStore",
        "setPocButtonEnabled",
        "(Landroid/content/Context;Z)V",
        context.object(),
        static_cast<jboolean>(enabled));
#endif
}

void ReflectorClient::setLearnedHardwarePttKeyCode(int keyCode)
{
    const int normalizedKeyCode = keyCode > 0 ? keyCode : kNoLearnedHardwarePttKeyCode;
    if (m_learnedHardwarePttKeyCode == normalizedKeyCode) {
        return;
    }

    m_learnedHardwarePttKeyCode = normalizedKeyCode;
    emit hardwarePttSettingsChanged();

#if defined(Q_OS_ANDROID)
    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: Failed to get Android context for learned hardware PTT key";
        return;
    }

    if (normalizedKeyCode == kNoLearnedHardwarePttKeyCode) {
        QJniObject::callStaticMethod<void>(
            "yo6say/latry/HardwarePttSettingsStore",
            "clearLearnedPttKeyCode",
            "(Landroid/content/Context;)V",
            context.object());
        return;
    }

    QJniObject::callStaticMethod<void>(
        "yo6say/latry/HardwarePttSettingsStore",
        "setLearnedPttKeyCode",
        "(Landroid/content/Context;I)V",
        context.object(),
        static_cast<jint>(normalizedKeyCode));
#endif
}

void ReflectorClient::clearLearnedHardwarePttKeyCode()
{
    setLearnedHardwarePttKeyCode(kNoLearnedHardwarePttKeyCode);
}

void ReflectorClient::startHardwarePttLearning()
{
    if (m_hardwarePttLearningActive) {
        return;
    }

#if defined(Q_OS_ANDROID)
    QJniObject activity = androidQtContext();
    if (!activity.isValid()) {
        qWarning() << "ReflectorClient: failed to get Android context for PTT learning";
        return;
    }
    const jboolean started = QJniObject::callStaticMethod<jboolean>(
        "yo6say/latry/HardwarePttLearningCoordinator",
        "startLearning",
        "(Landroid/content/Context;)Z",
        activity.object<jobject>());
    if (!started) {
        qWarning() << "ReflectorClient: Failed to start hardware PTT learning";
        return;
    }
#endif

    m_hardwarePttLearningActive = true;
    m_hardwarePttLearningResult = 0; // RESULT_NONE
    emit hardwarePttLearningActiveChanged();
    emit hardwarePttLearningResultChanged();
}

void ReflectorClient::cancelHardwarePttLearning()
{
    if (!m_hardwarePttLearningActive) {
        return;
    }

#if defined(Q_OS_ANDROID)
    QJniObject::callStaticMethod<void>(
        "yo6say/latry/HardwarePttLearningCoordinator",
        "cancelLearning",
        "()V");
#endif
    // The native callback (notifyHardwarePttLearningResult) will update state
}

void ReflectorClient::setLiveTranscriptionEnabled(bool enabled)
{
    if (!enabled) {
        m_transcriptionPermissionEnablePending = false;
    }

#if defined(Q_OS_ANDROID)
    if (enabled) {
        if (!m_transcriptionAvailable) {
            m_transcriptionPermissionEnablePending = false;
            return;
        }

        if (!hasAuthorizedRecordAudioPermission()) {
            m_transcriptionPermissionEnablePending = true;
            requestRecordAudioPermissionIfNeeded();
            return;
        }
    }
#else
    Q_UNUSED(enabled)
    return;
#endif

    if (m_liveTranscriptionEnabled == enabled) {
        return;
    }

    m_liveTranscriptionEnabled = enabled;
    emit liveTranscriptionEnabledChanged();

#if defined(Q_OS_ANDROID)
    if (!m_liveTranscriptionEnabled) {
        m_transcriptionSuspendedByPause = false;
        stopTranscriptionSession(true);
        return;
    }

    if (m_isReceivingAudio) {
        startTranscriptionSession();
    }
#endif
}

#if defined(Q_OS_ANDROID)
bool ReflectorClient::hasAuthorizedRecordAudioPermission() const
{
    auto permission = QtAndroidPrivate::checkPermission(kRecordAudioPermission);
    permission.waitForFinished();

    const auto result = permissionResultFromFuture(
        permission,
        "QtAndroidPrivate::checkPermission(RECORD_AUDIO)");
    return result.has_value()
            && result.value() == QtAndroidPrivate::PermissionResult::Authorized;
}

void ReflectorClient::refreshHardwarePttSettings()
{
    const QJniObject context = androidQtContext();
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: Failed to get Android context for hardware PTT refresh";
        return;
    }

    const bool hardwarePttEnabled = QJniObject::callStaticMethod<jboolean>(
        "yo6say/latry/HardwarePttSettingsStore",
        "isPocButtonEnabled",
        "(Landroid/content/Context;)Z",
        context.object());
    const int learnedHardwarePttKeyCode = QJniObject::callStaticMethod<jint>(
        "yo6say/latry/HardwarePttSettingsStore",
        "getLearnedPttKeyCode",
        "(Landroid/content/Context;)I",
        context.object());
    const int normalizedLearnedKeyCode = learnedHardwarePttKeyCode > 0
            ? learnedHardwarePttKeyCode
            : kNoLearnedHardwarePttKeyCode;

    if (m_hardwarePttEnabled == hardwarePttEnabled
            && m_learnedHardwarePttKeyCode == normalizedLearnedKeyCode) {
        return;
    }

    m_hardwarePttEnabled = hardwarePttEnabled;
    m_learnedHardwarePttKeyCode = normalizedLearnedKeyCode;
    emit hardwarePttSettingsChanged();
}

void ReflectorClient::requestRecordAudioPermissionIfNeeded()
{
    if (m_recordAudioPermissionRequestPending) {
        qDebug() << "RECORD_AUDIO permission request already pending";
        return;
    }

    m_recordAudioPermissionRequestPending = true;
    const auto future = QtAndroidPrivate::requestPermission(kRecordAudioPermission);
    auto *watcher = new QFutureWatcher<QtAndroidPrivate::PermissionResult>(this);

    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, future]() mutable {
        m_recordAudioPermissionRequestPending = false;
        watcher->deleteLater();

        const auto result = permissionResultFromFuture(
            future,
            "QtAndroidPrivate::requestPermission(RECORD_AUDIO)");
        handleRecordAudioPermissionResult(
            result.has_value()
            && result.value() == QtAndroidPrivate::PermissionResult::Authorized);
    });

    watcher->setFuture(future);
}

void ReflectorClient::handleRecordAudioPermissionResult(bool authorized)
{
    const bool retryPtt = m_pttPermissionRestartPending;
    const bool enableTranscription = m_transcriptionPermissionEnablePending;

    m_pttPermissionRestartPending = false;
    m_transcriptionPermissionEnablePending = false;

    if (!authorized) {
        if (enableTranscription) {
            qWarning() << "Live transcription requires RECORD_AUDIO permission";
        }
        if (retryPtt) {
            qWarning() << "RECORD_AUDIO permission denied by user";
        }
        return;
    }

    if (enableTranscription) {
        setLiveTranscriptionEnabled(true);
    }

    if (retryPtt) {
        qDebug() << "RECORD_AUDIO permission granted, proceeding with PTT";
        QTimer::singleShot(100, this, [this]() {
            startTransmission();
        });
    }
}

void ReflectorClient::triggerTxTimeoutWarningHaptic()
{
    const QJniObject context = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: failed to get Android context for TOT warning haptic";
        return;
    }

    QJniObject::callStaticMethod<void>(
        "yo6say/latry/LatryActivity",
        "vibrateTotWarning",
        "(Landroid/content/Context;)V",
        context.object());
}
#endif

void ReflectorClient::downloadTranscriptionModel(const QString &languageTag)
{
#if defined(Q_OS_ANDROID)
    const QString normalizedLanguageTag = languageTag.trimmed();
    if (m_transcriptionModelDownloadInProgress) {
        return;
    }

    const QJniObject context = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: failed to get Android context to download speech model";
        return;
    }

    bool requested = false;
    if (normalizedLanguageTag.isEmpty()) {
        if (m_transcriptionAvailable) {
            return;
        }

        requested = QJniObject::callStaticMethod<jboolean>(
            "yo6say/latry/LatryTranscriptionManager",
            "requestTranscriptionModelDownload",
            "(Landroid/content/Context;)Z",
            context.object());
    } else {
        const QJniObject javaLanguageTag = QJniObject::fromString(normalizedLanguageTag);
        requested = QJniObject::callStaticMethod<jboolean>(
            "yo6say/latry/LatryTranscriptionManager",
            "requestTranscriptionModelDownload",
            "(Landroid/content/Context;Ljava/lang/String;)Z",
            context.object(),
            javaLanguageTag.object<jstring>());
    }
    if (requested) {
        setTranscriptionModelDownloadState(true,
                                           true,
                                           0,
                                           normalizedLanguageTag.isEmpty()
                                                   ? QStringLiteral("Requesting on-device speech model download")
                                                   : QStringLiteral("Requesting on-device speech model download for %1")
                                                         .arg(normalizedLanguageTag));
    }

    refreshTranscriptionSupportState();
#endif
}

void ReflectorClient::openTranscriptionSettings()
{
#if defined(Q_OS_ANDROID)
    const QJniObject context = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: failed to get Android context to open transcription settings";
        return;
    }

    const bool opened = QJniObject::callStaticMethod<jboolean>(
        "yo6say/latry/LatryTranscriptionManager",
        "openTranscriptionSettings",
        "(Landroid/content/Context;)Z",
        context.object());
    if (!opened) {
        qWarning() << "ReflectorClient: failed to open Android voice input settings";
    }
#endif
}

void ReflectorClient::updateTxTimeoutWarningState()
{
    const int remainingSeconds = m_txTimeoutSeconds - m_txSeconds;
    const bool warningActive = m_txTimeoutEnabled
            && m_pttActive
            && !m_pttReleasePending
            && !m_txStopPending
            && remainingSeconds <= kTxTimeoutWarningWindowSeconds
            && remainingSeconds > 0;

    if (m_txTimeoutWarning == warningActive) {
        return;
    }

    m_txTimeoutWarning = warningActive;
    emit txTimeoutWarningChanged();
}

void ReflectorClient::refreshConnectionStatus()
{
    if (m_state != Connected) {
        return;
    }

    m_connectionStatus = (m_talkgroup == 0)
            ? QStringLiteral("Connected in monitor mode")
            : QStringLiteral("Connected to TG %1").arg(m_talkgroup);
    emit connectionStatusChanged();
#if defined(Q_OS_ANDROID)
    updateServiceSelectedTalkgroup(m_talkgroup);
    updateServiceConnectionStatus(m_connectionStatus, true);
#endif
}

void ReflectorClient::refreshMonitoredTalkgroupsModel()
{
    emit monitoredTalkgroupsChanged(m_monitoredTalkgroups);
    emit monitoredTalkgroupsModelChanged();
}

void ReflectorClient::setReceivingAudioState(bool receiving)
{
    if (m_isReceivingAudio == receiving) {
#if defined(Q_OS_ANDROID)
        if (!receiving) {
            m_transcriptionSuspendedByPause = false;
        }
#endif
        if (!receiving) {
            stopTranscriptionSession(true);
        }
        return;
    }

    m_isReceivingAudio = receiving;
    if (!receiving) {
        m_audioTimeoutTimer->stop();
    }
    emit isReceivingAudioChanged();

    if (receiving) {
#if defined(Q_OS_ANDROID)
        updateServiceReceiveState(true, m_currentTalker);
        m_transcriptionSuspendedByPause = false;
#endif
        if (m_liveTranscriptionEnabled) {
            startTranscriptionSession();
        }
        return;
    }

#if defined(Q_OS_ANDROID)
    updateServiceReceiveState(false, QString());
    m_transcriptionSuspendedByPause = false;
#endif
    stopTranscriptionSession(true);
}

void ReflectorClient::checkTranscriptionAvailability(bool androidServiceLaunch)
{
    setTranscriptionAvailable(false);
    setTranscriptionLanguageModels(QStringList{}, QStringList{}, QStringList{}, QString());
    setTranscriptionModelDownloadState(false, false, -1, QString());
    if (m_transcriptionSupportRefreshTimer) {
        m_transcriptionSupportRefreshTimer->stop();
    }

#if defined(Q_OS_ANDROID)
    if (androidServiceLaunch) {
        return;
    }

    refreshTranscriptionSupportState();
#else
    Q_UNUSED(androidServiceLaunch)
#endif
}

void ReflectorClient::refreshTranscriptionSupportState()
{
#if defined(Q_OS_ANDROID)
    const QJniObject context = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: failed to get Android context for transcription support";
        setTranscriptionAvailable(false);
        setTranscriptionLanguageModels(QStringList{}, QStringList{}, QStringList{}, QString());
        setTranscriptionModelDownloadState(false, false, -1, QString());
        return;
    }

    const QJniObject supportJson = QJniObject::callStaticObjectMethod(
        "yo6say/latry/LatryTranscriptionManager",
        "getTranscriptionSupportJson",
        "(Landroid/content/Context;)Ljava/lang/String;",
        context.object());
    const QString jsonText = supportJson.toString();
    if (jsonText.isEmpty()) {
        qWarning() << "ReflectorClient: empty transcription support state from Android";
        setTranscriptionAvailable(false);
        setTranscriptionLanguageModels(QStringList{}, QStringList{}, QStringList{}, QString());
        setTranscriptionModelDownloadState(false, false, -1, QString());
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument supportDocument =
            QJsonDocument::fromJson(jsonText.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !supportDocument.isObject()) {
        qWarning() << "ReflectorClient: failed to parse transcription support state"
                   << parseError.errorString() << jsonText;
        setTranscriptionAvailable(false);
        setTranscriptionLanguageModels(QStringList{}, QStringList{}, QStringList{}, QString());
        setTranscriptionModelDownloadState(false, false, -1, QString());
        return;
    }

    const QJsonObject supportObject = supportDocument.object();
    const QStringList installedLanguages =
            jsonStringList(supportObject.value(QStringLiteral("installedLanguages")));
    const QStringList pendingLanguages =
            jsonStringList(supportObject.value(QStringLiteral("pendingLanguages")));
    const QStringList supportedLanguages =
            jsonStringList(supportObject.value(QStringLiteral("supportedLanguages")));
    const QString downloadTargetLanguage =
            supportObject.value(QStringLiteral("downloadTargetLanguage")).toString().trimmed();

    setTranscriptionAvailable(supportObject.value(QStringLiteral("available")).toBool(false));
    setTranscriptionLanguageModels(installedLanguages,
                                   pendingLanguages,
                                   supportedLanguages,
                                   downloadTargetLanguage);
    setTranscriptionModelDownloadState(
        supportObject.value(QStringLiteral("canDownload")).toBool(false),
        supportObject.value(QStringLiteral("downloadInProgress")).toBool(false),
        supportObject.value(QStringLiteral("downloadProgress")).toInt(-1),
        supportObject.value(QStringLiteral("statusMessage")).toString());
#endif
}

void ReflectorClient::startTranscriptionSession()
{
#if defined(Q_OS_ANDROID)
    if (!m_liveTranscriptionEnabled || !m_transcriptionAvailable
            || !m_isReceivingAudio || !m_audioEngine || m_transcriptionSessionActive) {
        return;
    }

    m_transcriptionPendingText.clear();
    m_lastFinalTranscriptionSegment.clear();
    updateTranscriptionDisplay();

    const QJniObject context = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "getContext",
        "()Landroid/content/Context;");
    if (!context.isValid()) {
        qWarning() << "ReflectorClient: failed to get Android context to start live transcription";
        return;
    }

    const jint writeFd = QJniObject::callStaticMethod<jint>(
        "yo6say/latry/LatryTranscriptionManager",
        "createPipeAndStart",
        "(Landroid/content/Context;)I",
        context.object());
    if (writeFd < 0) {
        qWarning() << "ReflectorClient: live transcription session failed to start";
        return;
    }

    const bool forwarded = QMetaObject::invokeMethod(
        m_audioEngine,
        "setTranscriptionPipeFd",
        Qt::BlockingQueuedConnection,
        Q_ARG(int, static_cast<int>(writeFd)));
    if (!forwarded) {
        ::close(writeFd);
        QJniObject::callStaticMethod<void>("yo6say/latry/LatryTranscriptionManager",
                                           "stopTranscription",
                                           "()V");
        qWarning() << "ReflectorClient: failed to forward transcription pipe to AudioEngine";
        return;
    }

    m_transcriptionSessionActive = true;
#endif
}

void ReflectorClient::stopTranscriptionSession(bool clearText)
{
#if defined(Q_OS_ANDROID)
    const bool hadActiveSession = m_transcriptionSessionActive;
    m_transcriptionSessionActive = false;

    if (m_audioEngine && m_audioThread && m_audioThread->isRunning()) {
        QMetaObject::invokeMethod(
            m_audioEngine,
            "setTranscriptionPipeFd",
            Qt::BlockingQueuedConnection,
            Q_ARG(int, -1));
    }

    if (hadActiveSession) {
        QJniObject::callStaticMethod<void>("yo6say/latry/LatryTranscriptionManager",
                                           "stopTranscription",
                                           "()V");
    }
#endif

    if (clearText) {
        clearTranscriptionState();
    }
}

void ReflectorClient::setTranscriptionAvailable(bool available)
{
    if (m_transcriptionAvailable == available) {
        return;
    }

    m_transcriptionAvailable = available;
    emit transcriptionAvailabilityChanged();
}

void ReflectorClient::setTranscriptionLanguageModels(const QStringList &installedLanguages,
                                                     const QStringList &pendingLanguages,
                                                     const QStringList &supportedLanguages,
                                                     const QString &downloadTargetLanguage)
{
    QVariantList installedModels;
    installedModels.reserve(installedLanguages.size());
    for (const QString &languageTag : installedLanguages) {
        installedModels.append(buildTranscriptionLanguageEntry(languageTag,
                                                              true,
                                                              false,
                                                              false));
    }

    QVariantList downloadableModels;
    QStringList orderedDownloadableTags = pendingLanguages;
    for (const QString &languageTag : supportedLanguages) {
        if (!orderedDownloadableTags.contains(languageTag)) {
            orderedDownloadableTags.append(languageTag);
        }
    }

    downloadableModels.reserve(orderedDownloadableTags.size());
    for (const QString &languageTag : orderedDownloadableTags) {
        downloadableModels.append(buildTranscriptionLanguageEntry(
                languageTag,
                false,
                pendingLanguages.contains(languageTag),
                !downloadTargetLanguage.isEmpty() && downloadTargetLanguage == languageTag));
    }

    if (m_transcriptionInstalledLanguages == installedModels
            && m_transcriptionDownloadableLanguages == downloadableModels) {
        return;
    }

    m_transcriptionInstalledLanguages = installedModels;
    m_transcriptionDownloadableLanguages = downloadableModels;
    emit transcriptionLanguageModelsChanged();
}

void ReflectorClient::setTranscriptionModelDownloadState(bool available,
                                                         bool inProgress,
                                                         int progress,
                                                         const QString &status)
{
    bool changed = false;

    if (m_transcriptionModelDownloadAvailable != available) {
        m_transcriptionModelDownloadAvailable = available;
        changed = true;
    }
    if (m_transcriptionModelDownloadInProgress != inProgress) {
        m_transcriptionModelDownloadInProgress = inProgress;
        changed = true;
    }
    if (m_transcriptionModelDownloadProgress != progress) {
        m_transcriptionModelDownloadProgress = progress;
        changed = true;
    }
    if (m_transcriptionModelDownloadStatus != status) {
        m_transcriptionModelDownloadStatus = status;
        changed = true;
    }

    if (m_transcriptionSupportRefreshTimer) {
        if (m_transcriptionModelDownloadInProgress) {
            m_transcriptionSupportRefreshTimer->start();
        } else {
            m_transcriptionSupportRefreshTimer->stop();
        }
    }

    if (changed) {
        emit transcriptionModelDownloadStateChanged();
    }
}

QString ReflectorClient::normalizeTranscriptionSnippet(const QString &text)
{
    return text.simplified();
}

void ReflectorClient::clearTranscriptionState()
{
    m_transcriptionCommittedText.clear();
    m_transcriptionPendingText.clear();
    m_lastFinalTranscriptionSegment.clear();
    updateTranscriptionDisplay();
}

void ReflectorClient::updateTranscriptionDisplay()
{
    QString nextText = trimTranscriptionTail(m_transcriptionCommittedText);
    const QString pending = trimTranscriptionTail(m_transcriptionPendingText);
    if (!pending.isEmpty()) {
        nextText = nextText.isEmpty() ? pending : nextText + QLatin1Char('\n') + pending;
    }

    nextText = trimTranscriptionTail(nextText);
    if (m_transcriptionText == nextText) {
        return;
    }

    m_transcriptionText = nextText;
    emit transcriptionTextChanged();
}

void ReflectorClient::handlePartialTranscription(const QString &text)
{
    if (!m_transcriptionSessionActive) {
        return;
    }

    m_transcriptionPendingText = normalizeTranscriptionSnippet(text);
    updateTranscriptionDisplay();
}

void ReflectorClient::handleFinalTranscription(const QString &text)
{
    if (!m_transcriptionSessionActive) {
        return;
    }

    const QString normalized = normalizeTranscriptionSnippet(text);
    m_transcriptionPendingText.clear();
    if (normalized.isEmpty()) {
        updateTranscriptionDisplay();
        return;
    }

    if (normalized != m_lastFinalTranscriptionSegment) {
        m_lastFinalTranscriptionSegment = normalized;
        m_transcriptionCommittedText = m_transcriptionCommittedText.isEmpty()
                ? normalized
                : trimTranscriptionTail(m_transcriptionCommittedText + QLatin1Char('\n') + normalized);
    }

    updateTranscriptionDisplay();
}

void ReflectorClient::handleTranscriptionError(int errorCode, const QString &message)
{
    qWarning() << "ReflectorClient: live transcription stopped after error"
               << errorCode << message;

    if (errorCode == kAndroidSpeechErrorLanguageNotSupported
            || errorCode == kAndroidSpeechErrorLanguageUnavailable) {
        const bool wasEnabled = m_liveTranscriptionEnabled;
        m_liveTranscriptionEnabled = false;
        if (wasEnabled) {
            emit liveTranscriptionEnabledChanged();
        }
        setTranscriptionAvailable(false);
        refreshTranscriptionSupportState();
    }

    m_transcriptionSessionActive = false;
    m_transcriptionPendingText.clear();
    stopTranscriptionSession(false);
    updateTranscriptionDisplay();
}

void ReflectorClient::setAudioRouteState(const QString &currentRoute, const QStringList &availableRouteIds)
{
    const QStringList orderedRouteIds = normalizedAudioRouteIds(availableRouteIds);
    const QVariantList routeModel = buildAudioRouteModel(orderedRouteIds);

    QString normalizedCurrentRoute = normalizeAudioRouteId(currentRoute);
    if (!orderedRouteIds.contains(normalizedCurrentRoute)) {
        normalizedCurrentRoute = orderedRouteIds.isEmpty() ? kAudioRouteSpeaker : orderedRouteIds.constFirst();
    }

    const bool availableRoutesChanged = (m_availableAudioRoutes != routeModel);
    const bool currentRouteChanged = (m_currentAudioRoute != normalizedCurrentRoute);

    if (availableRoutesChanged) {
        m_availableAudioRoutes = routeModel;
        emit availableAudioRoutesChanged();
    }

    if (currentRouteChanged) {
        m_currentAudioRoute = normalizedCurrentRoute;
        emit currentAudioRouteChanged();

        if (m_audioEngine) {
            QMetaObject::invokeMethod(m_audioEngine, "handleAudioRouteChanged", Qt::QueuedConnection);
        }
    }
}

void ReflectorClient::applyAudioLevelsToEngine()
{
    if (!m_audioEngine) {
        return;
    }

    QMetaObject::invokeMethod(m_audioEngine, "setRxAudioLevelDb",
                              Qt::QueuedConnection,
                              Q_ARG(float, static_cast<float>(m_rxAudioLevelDb)));
    QMetaObject::invokeMethod(m_audioEngine, "setTxAudioLevelDb",
                              Qt::QueuedConnection,
                              Q_ARG(float, static_cast<float>(m_txAudioLevelDb)));
}

void ReflectorClient::setRxMeterState(qreal level, qreal peakLevel)
{
    const qreal normalizedLevel = normalizeMeterLevel(level);
    const qreal normalizedPeakLevel = normalizeMeterLevel(peakLevel);

    if (m_rxMeterLevel != normalizedLevel) {
        m_rxMeterLevel = normalizedLevel;
        emit rxMeterLevelChanged();
    }
    if (m_rxMeterPeakLevel != normalizedPeakLevel) {
        m_rxMeterPeakLevel = normalizedPeakLevel;
        emit rxMeterPeakLevelChanged();
    }
}

void ReflectorClient::setTxMeterState(qreal level, qreal peakLevel)
{
    const qreal normalizedLevel = normalizeMeterLevel(level);
    const qreal normalizedPeakLevel = normalizeMeterLevel(peakLevel);

    if (m_txMeterLevel != normalizedLevel) {
        m_txMeterLevel = normalizedLevel;
        emit txMeterLevelChanged();
    }
    if (m_txMeterPeakLevel != normalizedPeakLevel) {
        m_txMeterPeakLevel = normalizedPeakLevel;
        emit txMeterPeakLevelChanged();
    }
}

void ReflectorClient::resetAudioMeters()
{
    setRxMeterState(0.0, 0.0);
    setTxMeterState(0.0, 0.0);
}

void ReflectorClient::resetTalkgroupSelectionTimer()
{
    if (m_talkgroup == 0) {
        stopTalkgroupSelectionTimer();
        return;
    }

    m_tgSelectTimeoutCounter = m_tgSelectTimeoutSeconds;
    if (m_state == Connected && !m_talkgroupSelectionTimer->isActive()) {
        m_talkgroupSelectionTimer->start();
    }
}

void ReflectorClient::stopTalkgroupSelectionTimer()
{
    m_tgSelectTimeoutCounter = 0;
    if (m_talkgroupSelectionTimer->isActive()) {
        m_talkgroupSelectionTimer->stop();
    }
}

void ReflectorClient::clearMonitoredTalkgroups()
{
    if (!m_monitoredTalkgroups.isEmpty()) {
        m_monitoredTalkgroups.clear();
        refreshMonitoredTalkgroupsModel();
    }
}

quint8 ReflectorClient::monitoredTalkgroupPriority(quint32 talkgroup) const
{
    for (const MonitoredTalkgroupEntry &entry : m_configuredMonitoredTalkgroups) {
        if (entry.talkgroup == talkgroup) {
            return entry.priority;
        }
    }
    return 0;
}

bool ReflectorClient::isTalkgroupMonitored(quint32 talkgroup) const
{
    return m_monitoredTalkgroups.contains(talkgroup);
}

bool ReflectorClient::shouldHandleTalkerStart(quint32 talkgroup)
{
    if (talkgroup == 0) {
        qWarning() << "Ignoring TALKER_START on TG 0 because TG 0 is only the local monitor parking state";
        return false;
    }

    if (talkgroup == m_talkgroup) {
        if (m_talkgroup > 0) {
            resetTalkgroupSelectionTimer();
        }
        return true;
    }

    if (!isTalkgroupMonitored(talkgroup)) {
        return false;
    }

    if (m_talkgroup == 0) {
        selectTalkgroupInternal(talkgroup, TalkgroupSelectionOrigin::RemoteActivation);
        return true;
    }

    if (!m_usePriorityMode) {
        return false;
    }

    const quint8 incomingPriority = monitoredTalkgroupPriority(talkgroup);
    const quint8 selectedPriority = monitoredTalkgroupPriority(m_talkgroup);
    if (incomingPriority > selectedPriority) {
        selectTalkgroupInternal(talkgroup, TalkgroupSelectionOrigin::RemotePriorityActivation);
        return true;
    }

    return false;
}

bool ReflectorClient::selectTalkgroupInternal(quint32 talkgroup, TalkgroupSelectionOrigin origin)
{
    const bool talkgroupChanged = (m_talkgroup != talkgroup);
    const bool manualSelection = (origin == TalkgroupSelectionOrigin::Manual
                                  || origin == TalkgroupSelectionOrigin::TxDefaultActivation);

    if (talkgroupChanged) {
        m_talkgroup = talkgroup;
        emit selectedTalkgroupChanged();
    }

    if (talkgroup == 0) {
        m_usePriorityMode = true;
        stopTalkgroupSelectionTimer();
    } else {
        if (manualSelection) {
            m_usePriorityMode = false;
        }
        resetTalkgroupSelectionTimer();
    }

    if (m_state != Connected) {
        qInfo() << "Stored talkgroup for next connection:" << m_talkgroup;
        return talkgroupChanged;
    }

    if (talkgroupChanged) {
        qInfo() << "Selecting talkgroup:" << m_talkgroup;
        sendSelectTG(m_talkgroup);
    }

    refreshConnectionStatus();
    return talkgroupChanged;
}

ReflectorClient::ParsedMonitoredTalkgroups ReflectorClient::parseMonitoredTalkgroupsSpec(
        const QString &monitoredTalkgroups, quint32 primaryTalkgroup)
{
    ParsedMonitoredTalkgroups parsed;
    QSet<quint32> seenConfigured;
    QStringList normalizedEntries;

    const QStringList rawEntries = monitoredTalkgroups.split(',', Qt::SkipEmptyParts);
    for (const QString &rawEntry : rawEntries) {
        const QString trimmedEntry = rawEntry.trimmed();
        if (trimmedEntry.isEmpty()) {
            continue;
        }

        int suffixStart = trimmedEntry.size();
        int priority = 0;
        while (suffixStart > 0 && trimmedEntry.at(suffixStart - 1) == QLatin1Char('+')) {
            ++priority;
            --suffixStart;
        }

        const QString talkgroupText = trimmedEntry.left(suffixStart).trimmed();
        bool ok = false;
        const quint32 talkgroup = talkgroupText.toUInt(&ok);
        if (!ok || talkgroup == 0 || seenConfigured.contains(talkgroup)) {
            continue;
        }

        MonitoredTalkgroupEntry entry;
        entry.talkgroup = talkgroup;
        entry.priority = static_cast<quint8>(qMin(priority, 255));
        parsed.configured.append(entry);
        seenConfigured.insert(talkgroup);
        normalizedEntries.append(QString::number(talkgroup) + QString(entry.priority, QLatin1Char('+')));
    }

    parsed.normalizedSpec = normalizedEntries.join(QLatin1Char(','));

    QSet<quint32> seenActive;
    if (primaryTalkgroup > 0) {
        parsed.activeTalkgroups.append(primaryTalkgroup);
        seenActive.insert(primaryTalkgroup);
    }

    for (const MonitoredTalkgroupEntry &entry : parsed.configured) {
        if (!seenActive.contains(entry.talkgroup)) {
            parsed.activeTalkgroups.append(entry.talkgroup);
            seenActive.insert(entry.talkgroup);
        }
    }

    return parsed;
}

void ReflectorClient::applyMonitoredTalkgroups(const QString &monitoredTalkgroups)
{
    const ParsedMonitoredTalkgroups parsed = parseMonitoredTalkgroupsSpec(monitoredTalkgroups, m_defaultTalkgroup);
    m_monitoredTalkgroupsSpec = parsed.normalizedSpec;
    m_configuredMonitoredTalkgroups = parsed.configured;

    if (m_monitoredTalkgroups != parsed.activeTalkgroups) {
        m_monitoredTalkgroups = parsed.activeTalkgroups;
        refreshMonitoredTalkgroupsModel();
    }
}

void ReflectorClient::onTalkgroupSelectionTimer()
{
    if (m_state != Connected || m_talkgroup == 0 || m_tgSelectTimeoutCounter <= 0) {
        if (m_tgSelectTimeoutCounter <= 0) {
            stopTalkgroupSelectionTimer();
        }
        return;
    }

    if (m_pttActive || m_isReceivingAudio) {
        return;
    }

    --m_tgSelectTimeoutCounter;
    if (m_tgSelectTimeoutCounter == 0) {
        selectTalkgroupInternal(0, TalkgroupSelectionOrigin::Timeout);
    }
}

// --- Audio Engine Management ---

void ReflectorClient::setupAudio()
{
    if (m_audioEngine) {
        QMetaObject::invokeMethod(m_audioEngine, "setupAudio", Qt::QueuedConnection);
    }
}

void ReflectorClient::initializeAudioEngine()
{
    // Create audio thread with time-critical priority
    m_audioThread = new QThread(this);
    m_audioThread->setObjectName("AudioEngineThread");
    m_audioThread->start(QThread::TimeCriticalPriority);

    // Create audio engine and move to audio thread
    m_audioEngine = new AudioEngine();
    m_audioEngine->moveToThread(m_audioThread);

    // Connect signals from AudioEngine to ReflectorClient
    connect(m_audioEngine, &AudioEngine::audioReadyChanged, this, [this](bool ready) {
        m_audioReady = ready;
        emit audioReadyChanged();
#if defined(Q_OS_ANDROID)
        if (ready) {
            resumeAndroidPttAfterReconnectIfReady();
        }
#endif
    });

    connect(m_audioEngine, &AudioEngine::audioDataEncoded, this, &ReflectorClient::onAudioDataEncoded);
    connect(m_audioEngine, &AudioEngine::txDrainComplete, this, &ReflectorClient::onTxDrainComplete);
    connect(m_audioEngine, &AudioEngine::audioSetupFinished, this, &ReflectorClient::onAudioSetupFinished);
    connect(m_audioEngine, &AudioEngine::rxMeterLevelsChanged, this,
            [this](float level, float peakLevel) {
                setRxMeterState(level, peakLevel);
            });
    connect(m_audioEngine, &AudioEngine::txMeterLevelsChanged, this,
            [this](float level, float peakLevel) {
                setTxMeterState(level, peakLevel);
            });

    // Connect Android audio focus signals
    connect(this, &ReflectorClient::audioFocusLost, m_audioEngine, &AudioEngine::onAudioFocusLost);
    connect(this, &ReflectorClient::audioFocusPaused, m_audioEngine, &AudioEngine::onAudioFocusPaused);
    connect(this, &ReflectorClient::audioFocusGained, m_audioEngine, &AudioEngine::onAudioFocusGained);
    connect(this, &ReflectorClient::activityPaused, m_audioEngine, &AudioEngine::onActivityPaused);
    connect(this, &ReflectorClient::activityResumed, m_audioEngine, &AudioEngine::onActivityResumed);

    applyAudioLevelsToEngine();
}

#if defined(Q_OS_ANDROID)
void ReflectorClient::handleAndroidAudioRoutesChanged(const QString &currentRoute,
                                                      const QStringList &availableRoutes)
{
    setAudioRouteState(currentRoute, availableRoutes);
}
#endif

void ReflectorClient::onAudioSetupFinished()
{
    if (!m_audioReady) {
        m_audioReady = true;
        emit audioReadyChanged();
    }
#if defined(Q_OS_ANDROID)
    resumeAndroidPttAfterReconnectIfReady();
#endif
}