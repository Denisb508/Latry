#include "TrackStore.h"

#include <QDateTime>
#include <QDir>
#include <QDebug>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QUuid>
#include <QVariantMap>

TrackStore::TrackStore(QObject *parent)
    : QObject(parent),
      m_connectionName(
          QStringLiteral("latry-trackstore-%1")
              .arg(reinterpret_cast<quintptr>(this)))
{
    if (!openDatabase()) {
        qCritical() << "TrackStore: database open failed";
        return;
    }

    if (!createSchema()) {
        qCritical() << "TrackStore: schema creation failed";
        return;
    }

    restoreActiveSession();

    qInfo() << "TrackStore ready, session:"
            << m_currentSessionId
            << "pending points:"
            << pendingPointCount();
}

TrackStore::~TrackStore()
{
    if (m_db.isValid())
        m_db.close();

    m_db = QSqlDatabase();
    QSqlDatabase::removeDatabase(m_connectionName);
}

bool TrackStore::openDatabase()
{
    const QString dataDir =
        QStandardPaths::writableLocation(
            QStandardPaths::AppDataLocation);

    if (dataDir.isEmpty())
        return false;

    QDir().mkpath(dataDir);

    m_db =
        QSqlDatabase::addDatabase(
            QStringLiteral("QSQLITE"),
            m_connectionName);

    m_db.setDatabaseName(
        dataDir + QStringLiteral("/latry-tracks.sqlite"));

    if (!m_db.open()) {
        qCritical()
            << "TrackStore:"
            << m_db.lastError().text();
        return false;
    }

    return true;
}

bool TrackStore::createSchema()
{
    QSqlQuery q(m_db);

    if (!q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS track_sessions ("
        " session_id TEXT PRIMARY KEY,"
        " started_at TEXT NOT NULL,"
        " ended_at TEXT NULL,"
        " tracking_mode TEXT NOT NULL DEFAULT 'smart',"
        " active INTEGER NOT NULL DEFAULT 1"
        ")"))) {
        qCritical() << q.lastError().text();
        return false;
    }

    if (!q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS track_points ("
        " id INTEGER PRIMARY KEY AUTOINCREMENT,"
        " session_id TEXT NOT NULL,"
        " recorded_at TEXT NOT NULL,"
        " latitude REAL NOT NULL,"
        " longitude REAL NOT NULL,"
        " accuracy_m REAL NULL,"
        " speed_kmh REAL NULL,"
        " heading_deg REAL NULL,"
        " tracking_mode TEXT NOT NULL DEFAULT 'smart',"
        " synced INTEGER NOT NULL DEFAULT 0"
        ")"))) {
        qCritical() << q.lastError().text();
        return false;
    }

    if (!q.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS "
        "idx_track_points_session_time "
        "ON track_points(session_id, recorded_at)"))) {
        qCritical() << q.lastError().text();
        return false;
    }

    if (!q.exec(QStringLiteral(
        "CREATE INDEX IF NOT EXISTS "
        "idx_track_points_synced "
        "ON track_points(synced, id)"))) {
        qCritical() << q.lastError().text();
        return false;
    }

    return true;
}

void TrackStore::restoreActiveSession()
{
    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "SELECT session_id "
        "FROM track_sessions "
        "WHERE active=1 "
        "ORDER BY started_at DESC "
        "LIMIT 1"));

    if (q.exec() && q.next())
        m_currentSessionId = q.value(0).toString();
}

bool TrackStore::sessionActive() const
{
    return !m_currentSessionId.isEmpty();
}

QString TrackStore::currentSessionId() const
{
    return m_currentSessionId;
}

QString TrackStore::startSession(
    const QString &trackingMode)
{
    if (!m_db.isOpen())
        return {};

    if (!m_currentSessionId.isEmpty())
        return m_currentSessionId;

    const QString sessionId =
        QUuid::createUuid()
            .toString(QUuid::WithoutBraces);

    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "INSERT INTO track_sessions "
        "(session_id, started_at, tracking_mode, active) "
        "VALUES (?, ?, ?, 1)"));

    q.addBindValue(sessionId);
    q.addBindValue(
        QDateTime::currentDateTimeUtc()
            .toString(Qt::ISODateWithMs));
    q.addBindValue(trackingMode);

    if (!q.exec()) {
        qWarning()
            << "TrackStore startSession:"
            << q.lastError().text();
        return {};
    }

    m_currentSessionId = sessionId;
    emit sessionChanged();

    return sessionId;
}

bool TrackStore::stopSession()
{
    if (m_currentSessionId.isEmpty())
        return true;

    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "UPDATE track_sessions "
        "SET ended_at=?, active=0 "
        "WHERE session_id=?"));

    q.addBindValue(
        QDateTime::currentDateTimeUtc()
            .toString(Qt::ISODateWithMs));

    q.addBindValue(m_currentSessionId);

    if (!q.exec()) {
        qWarning()
            << "TrackStore stopSession:"
            << q.lastError().text();
        return false;
    }

    m_currentSessionId.clear();
    emit sessionChanged();

    return true;
}

bool TrackStore::addPoint(
    double latitude,
    double longitude,
    double accuracyMeters,
    double speedKmh,
    double headingDeg,
    const QString &trackingMode)
{
    if (m_currentSessionId.isEmpty())
        return false;

    if (latitude < -90.0 || latitude > 90.0 ||
        longitude < -180.0 || longitude > 180.0) {
        return false;
    }

    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "INSERT INTO track_points "
        "(session_id, recorded_at, latitude, longitude, "
        " accuracy_m, speed_kmh, heading_deg, "
        " tracking_mode, synced) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)"));

    q.addBindValue(m_currentSessionId);

    q.addBindValue(
        QDateTime::currentDateTimeUtc()
            .toString(Qt::ISODateWithMs));

    q.addBindValue(latitude);
    q.addBindValue(longitude);
    q.addBindValue(accuracyMeters);
    q.addBindValue(speedKmh);
    q.addBindValue(headingDeg);
    q.addBindValue(trackingMode);

    if (!q.exec()) {
        qWarning()
            << "TrackStore addPoint:"
            << q.lastError().text();
        return false;
    }

    emit pointsChanged();
    return true;
}

int TrackStore::pendingPointCount() const
{
    if (!m_db.isOpen())
        return 0;

    QSqlQuery q(m_db);

    if (!q.exec(QStringLiteral(
        "SELECT COUNT(*) "
        "FROM track_points "
        "WHERE synced=0"))) {
        return 0;
    }

    return q.next()
        ? q.value(0).toInt()
        : 0;
}

QVariantList TrackStore::currentTrack() const
{
    QVariantList result;

    if (!m_db.isOpen())
        return result;

    QString sessionId = m_currentSessionId;

    if (sessionId.isEmpty()) {
        QSqlQuery latest(m_db);

        if (latest.exec(QStringLiteral(
                "SELECT session_id "
                "FROM track_sessions "
                "ORDER BY started_at DESC "
                "LIMIT 1"))
                && latest.next()) {
            sessionId = latest.value(0).toString();
        }
    }

    if (sessionId.isEmpty())
        return result;

    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "SELECT id, recorded_at, "
        "latitude, longitude, accuracy_m, "
        "speed_kmh, heading_deg, synced "
        "FROM track_points "
        "WHERE session_id=? "
        "ORDER BY id"));

    q.addBindValue(sessionId);

    if (!q.exec())
        return result;

    while (q.next()) {
        QVariantMap point;

        point.insert(
            QStringLiteral("id"),
            q.value(0));

        point.insert(
            QStringLiteral("recorded_at"),
            q.value(1));

        point.insert(
            QStringLiteral("lat"),
            q.value(2));

        point.insert(
            QStringLiteral("lon"),
            q.value(3));

        point.insert(
            QStringLiteral("accuracy_m"),
            q.value(4));

        point.insert(
            QStringLiteral("speed_kmh"),
            q.value(5));

        point.insert(
            QStringLiteral("heading_deg"),
            q.value(6));

        point.insert(
            QStringLiteral("synced"),
            q.value(7));

        result.append(point);
    }

    return result;
}

QVariantList TrackStore::pendingPoints(int limit) const
{
    QVariantList result;

    if (!m_db.isOpen())
        return result;

    if (limit < 1)
        limit = 1;
    if (limit > 200)
        limit = 200;

    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "SELECT id, session_id, recorded_at, "
        "latitude, longitude, accuracy_m, "
        "speed_kmh, heading_deg, tracking_mode "
        "FROM track_points "
        "WHERE synced=0 "
        "ORDER BY id "
        "LIMIT ?"));

    q.addBindValue(limit);

    if (!q.exec()) {
        qWarning()
            << "TrackStore pendingPoints:"
            << q.lastError().text();
        return result;
    }

    while (q.next()) {
        QVariantMap point;

        point.insert(QStringLiteral("id"), q.value(0));
        point.insert(QStringLiteral("session_id"), q.value(1));
        point.insert(QStringLiteral("recorded_at"), q.value(2));
        point.insert(QStringLiteral("lat"), q.value(3));
        point.insert(QStringLiteral("lon"), q.value(4));
        point.insert(QStringLiteral("accuracy_m"), q.value(5));
        point.insert(QStringLiteral("speed_kmh"), q.value(6));
        point.insert(QStringLiteral("heading_deg"), q.value(7));
        point.insert(QStringLiteral("tracking_mode"), q.value(8));

        result.append(point);
    }

    return result;
}

bool TrackStore::markPointSynced(qint64 pointId)
{
    if (!m_db.isOpen() || pointId <= 0)
        return false;

    QSqlQuery q(m_db);

    q.prepare(QStringLiteral(
        "UPDATE track_points "
        "SET synced=1 "
        "WHERE id=?"));

    q.addBindValue(pointId);

    if (!q.exec()) {
        qWarning()
            << "TrackStore markPointSynced:"
            << q.lastError().text();
        return false;
    }

    emit pointsChanged();
    return true;
}
