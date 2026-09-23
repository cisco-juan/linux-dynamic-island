#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Posts a notification to the session bus through
// `org.freedesktop.Notifications.Notify`, so an island reminder also lands in
// KDE's notification history (and may trigger KDE's own popup).
//
// Exposed to QML as the `EventNotifier` singleton. The D-Bus call is fire and
// forget: a missing daemon only produces a warning, never a failure.
class EventNotifier : public QObject
{
    Q_OBJECT

public:
    explicit EventNotifier(QObject *parent = nullptr);

    static EventNotifier *instance();

    // `appName` is shown as the notification source; `icon` is a themed icon
    // name. Returns true when the call was dispatched.
    Q_INVOKABLE bool post(const QString &appName, const QString &summary,
                          const QString &body, const QString &icon);
};
