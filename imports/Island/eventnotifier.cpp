#include "eventnotifier.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QLoggingCategory>
#include <QStringList>

EventNotifier::EventNotifier(QObject *parent)
    : QObject(parent)
{
}

EventNotifier *EventNotifier::instance()
{
    // Leaked on purpose: the singleton must outlive every QML engine.
    static EventNotifier *notifier = new EventNotifier();
    return notifier;
}

bool EventNotifier::post(const QString &appName, const QString &summary,
                         const QString &body, const QString &icon)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning("dynamic-island: session bus unavailable; reminder not posted");
        return false;
    }

    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("Notify"));

    // Notify(app_name, replaces_id, app_icon, summary, body, actions, hints,
    //        expire_timeout)
    //
    // The daemon's introspection requires the signature `susssasa{sv}i`:
    // `actions` must be an array of strings (`as`), so it is a QStringList.
    // A QVariantList marshals as `av` and the daemon rejects the call with
    // UnknownMethod. `hints` stays a QVariantMap (`a{sv}`).
    message << appName << 0u << icon << summary << body
            << QStringList() << QVariantMap() << -1;

    // Fire and forget: never block the GUI thread on the daemon.
    const bool sent = bus.send(message);
    if (!sent)
        qWarning("dynamic-island: failed to post reminder notification");
    return sent;
}
