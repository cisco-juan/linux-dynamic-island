#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// Calendar events owned by the island itself.
//
// No KDE PIM (Akonadi/KOrganizer) is installed, so events live in a plain JSON
// file persisted atomically with QSaveFile at
// `<ConfigLocation>/dynamic-island/events.json`. The store is exposed to QML as
// the `EventStore` singleton (module `Island`) and is the single source of
// truth for the agenda page and the calendar dots.
//
// Event shape (one JSON object per entry):
//   { "id", "title", "date" ("YYYY-MM-DD"), "time" ("HH:MM", empty = all-day),
//     "note", "reminderMinutes" (-1 = off), "reminderFired" (bool) }
//
// A 30 s timer drives reminders. For every event with a time, a non-negative
// lead and `reminderFired == false`:
//   - if now is within [start - lead, start + 5 min] -> emit reminderDue() and
//     mark fired (persisted), so it fires exactly once;
//   - if now is past start + 5 min -> mark fired silently, so a reminder missed
//     by more than the grace window never nags later.
//
// The instance is intentionally leaked: it must outlive every QML engine. The
// plugin registers it through a provider and pins CppOwnership.
class EventStore : public QObject
{
    Q_OBJECT
    // Monotonic change counter. A QML binding that only calls an Q_INVOKABLE
    // registers no dependency (function calls do not notify), so derived
    // bindings read this property instead to refresh on every mutation.
    Q_PROPERTY(int revision READ revision NOTIFY eventsChanged)

public:
    explicit EventStore(QObject *parent = nullptr);
    ~EventStore() override;

    // The process-wide instance backing the QML singleton.
    static EventStore *instance();

    // Events on one ISO date, sorted by time; all-day events first.
    Q_INVOKABLE QVariantList eventsForDate(const QString &isoDate) const;
    // Creates an event and returns its new id (-1 when the date is invalid).
    Q_INVOKABLE int addEvent(const QString &title, const QString &isoDate,
                             const QString &time, int reminderMinutes);
    // Removes an event; returns true when it existed.
    Q_INVOKABLE bool removeEvent(int id);
    // Updates the given fields ("title", "date", "time", "note",
    // "reminderMinutes"); returns true when the event existed.
    Q_INVOKABLE bool updateEvent(int id, const QVariantMap &fields);
    // Events in a month, in no particular order.
    Q_INVOKABLE QVariantList eventsInMonth(int year, int month) const;
    // ISO dates that have at least one event, so the calendar does not query
    // per cell.
    Q_INVOKABLE QStringList datesWithEvents() const;

    // Path of the backing JSON file (for debug output/documentation).
    Q_INVOKABLE QString filePath() const { return m_filePath; }

    // Change counter (see the Q_PROPERTY above).
    int revision() const { return m_revision; }

signals:
    void eventsChanged();
    // Emitted once per due reminder; `event` carries the full event map.
    void reminderDue(const QVariantMap &event);

private slots:
    void checkReminders();

private:
    void load();
    void save();
    QVariantMap *find(int id);

    static QString normalizeDate(const QString &isoDate);
    static QString normalizeTime(const QString &time);
    // "HH:MM" -> minutes since midnight; -1 for empty/all-day.
    static int timeToMinutes(const QString &time);

    QString m_filePath;
    // Insertion order is preserved; queries sort on the fly.
    QList<QVariantMap> m_events;
    QTimer m_reminderTimer;
    int m_revision = 0;
};
