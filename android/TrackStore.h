#pragma once

#include <QObject>
#include <QVariantList>
#include <QSqlDatabase>

class TrackStore : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool sessionActive
               READ sessionActive
               NOTIFY sessionChanged)

    Q_PROPERTY(QString currentSessionId
               READ currentSessionId
               NOTIFY sessionChanged)

    Q_PROPERTY(int pendingPointCount
               READ pendingPointCount
               NOTIFY pointsChanged)

public:
    explicit TrackStore(QObject *parent = nullptr);
    ~TrackStore() override;

    bool sessionActive() const;
    QString currentSessionId() const;
    int pendingPointCount() const;

    Q_INVOKABLE QString startSession(
        const QString &trackingMode = QStringLiteral("smart"));

    Q_INVOKABLE bool stopSession();

    Q_INVOKABLE bool addPoint(
        double latitude,
        double longitude,
        double accuracyMeters,
        double speedKmh,
        double headingDeg,
        const QString &trackingMode);

    Q_INVOKABLE QVariantList currentTrack() const;

    Q_INVOKABLE QVariantList pendingPoints(
        int limit = 50) const;

    Q_INVOKABLE bool markPointSynced(
        qint64 pointId);

signals:
    void sessionChanged();
    void pointsChanged();

private:
    bool openDatabase();
    bool createSchema();
    void restoreActiveSession();

    QString m_connectionName;
    QString m_currentSessionId;
    QSqlDatabase m_db;
};
