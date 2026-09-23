#pragma once

#include <QObject>
#include <QTimer>
#include <QVariant>

#include <functional>

// Controls screen backlight brightness through KDE PowerDevil's
// org.kde.Solid.PowerManagement.Actions.BrightnessControl D-Bus interface.
//
// The raw brightness range ([min, max]) is device-specific; this class exposes
// it as a 0..100 percentage. It subscribes to `brightnessChanged` so brightness
// keys and other clients stay in sync, and ignores the echo of its own
// `setBrightness` calls for a short window so it never fights an in-progress
// drag.
//
// Property reads are asynchronous (QDBusPendingCallWatcher): the GUI thread
// never blocks on PowerDevil, even if the daemon is unresponsive.
class BrightnessControl : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(int percent READ percent NOTIFY percentChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit BrightnessControl(QObject *parent = nullptr);

    bool available() const { return m_available; }
    int percent() const { return m_percent; }
    bool active() const { return m_active; }
    void setActive(bool active);

public slots:
    void setPercent(int percent);

signals:
    void availableChanged();
    void percentChanged();
    void activeChanged();

private slots:
    void refresh();
    void onBrightnessChanged(int value);
    void onBrightnessMaxChanged(int value);

private:
    void requestAsync(const QString &method,
                      const std::function<void(const QVariant &)> &callback);
    bool suppressed() const;
    void publishPercent();

    int m_raw = 0;
    int m_min = 0;
    int m_max = 0;
    int m_percent = 0;
    bool m_available = false;
    bool m_active = false;
    // True while a refresh chain is in flight, so polls do not pile up.
    bool m_refreshing = false;
    qint64 m_suppressUntilMs = 0;
    QTimer m_pollTimer;
};
