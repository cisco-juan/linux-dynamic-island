#include "eventstore.h"

#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTime>

#include <algorithm>

namespace {

constexpr int kReminderTickMs = 30 * 1000;
constexpr int kMissedGraceMinutes = 5;
constexpr int kMaxReminderMinutes = 120;

// Reminder leads are clamped to [-1, 120]: any negative value means "Off"
// (-1), and anything above two hours is capped. Both add and update normalize
// through this, so the stored value is always in range.
int clampReminderMinutes(int minutes)
{
    if (minutes < 0)
        return -1;
    return qMin(minutes, kMaxReminderMinutes);
}

} // namespace

EventStore::EventStore(QObject *parent)
    : QObject(parent)
{
    const QString configDir =
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/dynamic-island");
    QDir().mkpath(configDir);
    m_filePath = configDir + QStringLiteral("/events.json");

    load();

    // The production tick is 30 s. `ISLAND_REMINDER_TICK_MS` overrides it so
    // the verification harness can exercise the due/missed paths in seconds
    // instead of minutes; it has no effect unless set.
    int tickMs = kReminderTickMs;
    bool ok = false;
    const int override = qEnvironmentVariableIntValue("ISLAND_REMINDER_TICK_MS", &ok);
    if (ok && override > 0)
        tickMs = override;

    m_reminderTimer.setInterval(tickMs);
    connect(&m_reminderTimer, &QTimer::timeout, this, &EventStore::checkReminders);
    m_reminderTimer.start();
}

EventStore::~EventStore() = default;

EventStore *EventStore::instance()
{
    // Leaked on purpose: the singleton must outlive every QML engine.
    static EventStore *store = new EventStore();
    return store;
}

QString EventStore::normalizeDate(const QString &isoDate)
{
    const QDate date = QDate::fromString(isoDate.trimmed(), QStringLiteral("yyyy-MM-dd"));
    return date.isValid() ? date.toString(QStringLiteral("yyyy-MM-dd")) : QString();
}

QString EventStore::normalizeTime(const QString &time)
{
    const QString trimmed = time.trimmed();
    if (trimmed.isEmpty())
        return QString();
    // Accept "H:MM" as well as "HH:MM" and emit a canonical "HH:MM".
    const QTime parsed = QTime::fromString(trimmed, QStringLiteral("HH:mm"));
    if (parsed.isValid())
        return parsed.toString(QStringLiteral("HH:mm"));
    const QTime relaxed = QTime::fromString(trimmed, QStringLiteral("H:mm"));
    return relaxed.isValid() ? relaxed.toString(QStringLiteral("HH:mm")) : QString();
}

int EventStore::timeToMinutes(const QString &time)
{
    const QTime parsed = QTime::fromString(time, QStringLiteral("HH:mm"));
    if (!parsed.isValid())
        return -1;
    return parsed.hour() * 60 + parsed.minute();
}

void EventStore::load()
{
    m_events.clear();

    QFile file(m_filePath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return;

    const QByteArray raw = file.readAll();
    file.close();

    QJsonParseError error {};
    const QJsonDocument document = QJsonDocument::fromJson(raw, &error);
    if (error.error != QJsonParseError::NoError || !document.isArray()) {
        qWarning("dynamic-island: could not parse %s; starting with an empty store",
                 qPrintable(m_filePath));
        return;
    }

    const QJsonArray array = document.array();
    for (const QJsonValue &value : array) {
        if (!value.isObject())
            continue;
        const QJsonObject object = value.toObject();
        const QString date = normalizeDate(object.value(QStringLiteral("date")).toString());
        if (date.isEmpty())
            continue;
        QVariantMap event;
        event.insert(QStringLiteral("id"),
                     object.value(QStringLiteral("id")).toInt(-1));
        event.insert(QStringLiteral("title"),
                     object.value(QStringLiteral("title")).toString());
        event.insert(QStringLiteral("date"), date);
        event.insert(QStringLiteral("time"),
                     normalizeTime(object.value(QStringLiteral("time")).toString()));
        event.insert(QStringLiteral("note"),
                     object.value(QStringLiteral("note")).toString());
        event.insert(QStringLiteral("reminderMinutes"),
                     object.value(QStringLiteral("reminderMinutes")).toInt(-1));
        event.insert(QStringLiteral("reminderFired"),
                     object.value(QStringLiteral("reminderFired")).toBool(false));
        m_events.append(event);
    }
}

void EventStore::save()
{
    QJsonArray array;
    for (const QVariantMap &event : m_events) {
        QJsonObject object;
        object.insert(QStringLiteral("id"), event.value(QStringLiteral("id")).toInt());
        object.insert(QStringLiteral("title"), event.value(QStringLiteral("title")).toString());
        object.insert(QStringLiteral("date"), event.value(QStringLiteral("date")).toString());
        object.insert(QStringLiteral("time"), event.value(QStringLiteral("time")).toString());
        object.insert(QStringLiteral("note"), event.value(QStringLiteral("note")).toString());
        object.insert(QStringLiteral("reminderMinutes"),
                      event.value(QStringLiteral("reminderMinutes")).toInt());
        object.insert(QStringLiteral("reminderFired"),
                      event.value(QStringLiteral("reminderFired")).toBool());
        array.append(object);
    }

    // QSaveFile writes to a temporary file and renames on commit, so a crash
    // mid-write cannot leave a truncated events.json behind.
    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("dynamic-island: could not write %s", qPrintable(m_filePath));
        return;
    }
    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    if (!file.commit())
        qWarning("dynamic-island: could not commit %s", qPrintable(m_filePath));
}

QVariantMap *EventStore::find(int id)
{
    for (QVariantMap &event : m_events) {
        if (event.value(QStringLiteral("id")).toInt() == id)
            return &event;
    }
    return nullptr;
}

QVariantList EventStore::eventsForDate(const QString &isoDate) const
{
    const QString date = normalizeDate(isoDate);
    if (date.isEmpty())
        return {};

    QVariantList result;
    for (const QVariantMap &event : m_events) {
        if (event.value(QStringLiteral("date")).toString() == date)
            result.append(event);
    }

    std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap left = a.toMap();
        const QVariantMap right = b.toMap();
        const int leftMinutes =
            timeToMinutes(left.value(QStringLiteral("time")).toString());
        const int rightMinutes =
            timeToMinutes(right.value(QStringLiteral("time")).toString());
        // All-day events (no time) sort first.
        const int leftKey = leftMinutes < 0 ? -1 : leftMinutes;
        const int rightKey = rightMinutes < 0 ? -1 : rightMinutes;
        if (leftKey != rightKey)
            return leftKey < rightKey;
        return left.value(QStringLiteral("title")).toString()
               < right.value(QStringLiteral("title")).toString();
    });
    return result;
}

int EventStore::addEvent(const QString &title, const QString &isoDate,
                         const QString &time, int reminderMinutes)
{
    const QString date = normalizeDate(isoDate);
    if (date.isEmpty())
        return -1;

    int nextId = 1;
    for (const QVariantMap &event : m_events)
        nextId = qMax(nextId, event.value(QStringLiteral("id")).toInt() + 1);

    QVariantMap event;
    event.insert(QStringLiteral("id"), nextId);
    event.insert(QStringLiteral("title"), title.trimmed());
    event.insert(QStringLiteral("date"), date);
    event.insert(QStringLiteral("time"), normalizeTime(time));
    event.insert(QStringLiteral("note"), QString());
    event.insert(QStringLiteral("reminderMinutes"),
                 clampReminderMinutes(reminderMinutes));
    event.insert(QStringLiteral("reminderFired"), false);
    m_events.append(event);

    save();
    ++m_revision;
    emit eventsChanged();
    return nextId;
}

bool EventStore::removeEvent(int id)
{
    for (int i = 0; i < m_events.size(); ++i) {
        if (m_events.at(i).value(QStringLiteral("id")).toInt() == id) {
            m_events.removeAt(i);
            save();
            ++m_revision;
            emit eventsChanged();
            return true;
        }
    }
    return false;
}

bool EventStore::updateEvent(int id, const QVariantMap &fields)
{
    QVariantMap *event = find(id);
    if (!event)
        return false;

    bool scheduleChanged = false;
    for (auto it = fields.constBegin(); it != fields.constEnd(); ++it) {
        const QString key = it.key();
        if (key == QLatin1String("title")) {
            event->insert(key, it.value().toString().trimmed());
        } else if (key == QLatin1String("date")) {
            const QString date = normalizeDate(it.value().toString());
            if (date.isEmpty())
                continue;
            event->insert(key, date);
            scheduleChanged = true;
        } else if (key == QLatin1String("time")) {
            event->insert(key, normalizeTime(it.value().toString()));
            scheduleChanged = true;
        } else if (key == QLatin1String("note")) {
            event->insert(key, it.value().toString());
        } else if (key == QLatin1String("reminderMinutes")) {
            event->insert(key, clampReminderMinutes(it.value().toInt()));
            scheduleChanged = true;
        }
    }

    // A changed schedule gets a fresh chance to remind.
    if (scheduleChanged)
        event->insert(QStringLiteral("reminderFired"), false);

    save();
    ++m_revision;
    emit eventsChanged();
    return true;
}

QVariantList EventStore::eventsInMonth(int year, int month) const
{
    // `month` follows QML's 0-11 convention.
    QVariantList result;
    for (const QVariantMap &event : m_events) {
        const QDate date = QDate::fromString(event.value(QStringLiteral("date")).toString(),
                                             QStringLiteral("yyyy-MM-dd"));
        if (date.isValid() && date.year() == year && date.month() == month + 1)
            result.append(event);
    }
    return result;
}

QStringList EventStore::datesWithEvents() const
{
    QStringList dates;
    for (const QVariantMap &event : m_events) {
        const QString date = event.value(QStringLiteral("date")).toString();
        if (!dates.contains(date))
            dates.append(date);
    }
    return dates;
}

void EventStore::checkReminders()
{
    const QDateTime now = QDateTime::currentDateTime();
    bool changed = false;

    for (QVariantMap &event : m_events) {
        if (event.value(QStringLiteral("reminderFired")).toBool())
            continue;

        const QString date = event.value(QStringLiteral("date")).toString();
        const QString time = event.value(QStringLiteral("time")).toString();
        const int lead = event.value(QStringLiteral("reminderMinutes")).toInt();
        if (time.isEmpty() || lead < 0)
            continue;

        const QTime startTime = QTime::fromString(time, QStringLiteral("HH:mm"));
        const QDate startDate = QDate::fromString(date, QStringLiteral("yyyy-MM-dd"));
        if (!startTime.isValid() || !startDate.isValid())
            continue;

        const QDateTime start(startDate, startTime);
        // A reminder is due from `start - lead` until the end of the grace
        // window; `now` before the window simply waits for a later tick.
        const QDateTime windowStart = start.addSecs(-lead * 60);
        const QDateTime windowEnd = start.addSecs(kMissedGraceMinutes * 60);
        if (now < windowStart)
            continue;

        if (now <= windowEnd) {
            emit reminderDue(event);
            event.insert(QStringLiteral("reminderFired"), true);
            changed = true;
        } else {
            // Missed by more than the grace window: never nag later.
            event.insert(QStringLiteral("reminderFired"), true);
            changed = true;
        }
    }

    if (changed)
        save();
}
