#pragma once

#include <QObject>
#include <QScreen>
#include <QString>
#include <QStringList>
#include <QTimer>

// Persisted, user-editable configuration for the island, exposed to QML as the
// `IslandConfig` singleton (module `Island`).
//
// The single source of truth for the customize page: it stores the settings in
// `<ConfigLocation>/dynamic-island/config.ini` through QSettings and notifies
// QML on every change so the island can update live. Writes are debounced
// (~300 ms) so dragging a slider produces a single disk write on release.
//
// The instance is intentionally leaked: it must outlive every QML engine that
// binds to it. The plugin registers it as a singleton through a provider and
// pins CppOwnership so QML never deletes it.
class IslandConfig : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString alignment READ alignment WRITE setAlignment NOTIFY alignmentChanged)
    Q_PROPERTY(int topOffset READ topOffset WRITE setTopOffset NOTIFY topOffsetChanged)
    Q_PROPERTY(double scale READ scale WRITE setScale NOTIFY scaleChanged)
    Q_PROPERTY(double opacity READ opacity WRITE setOpacity NOTIFY opacityChanged)
    Q_PROPERTY(int animationDuration READ animationDuration WRITE setAnimationDuration
                   NOTIFY animationDurationChanged)
    Q_PROPERTY(QString easing READ easing WRITE setEasing NOTIFY easingChanged)
    Q_PROPERTY(QString screenMode READ screenMode WRITE setScreenMode NOTIFY screenModeChanged)
    Q_PROPERTY(QStringList screenNames READ screenNames NOTIFY screenNamesChanged)
    Q_PROPERTY(QScreen *targetScreen READ targetScreen NOTIFY targetScreenChanged)
    Q_PROPERTY(bool followActiveScreen READ followActiveScreen NOTIFY followActiveScreenChanged)
    Q_PROPERTY(int reminderLeadMinutes READ reminderLeadMinutes WRITE setReminderLeadMinutes
                   NOTIFY reminderLeadMinutesChanged)
    Q_PROPERTY(bool postReminders READ postReminders WRITE setPostReminders
                   NOTIFY postRemindersChanged)

public:
    explicit IslandConfig(QObject *parent = nullptr);
    ~IslandConfig() override;

    // The process-wide instance backing the QML singleton.
    static IslandConfig *instance();

    QString alignment() const { return m_alignment; }
    int topOffset() const { return m_topOffset; }
    double scale() const { return m_scale; }
    double opacity() const { return m_opacity; }
    int animationDuration() const { return m_animationDuration; }
    QString easing() const { return m_easing; }
    QString screenMode() const { return m_screenMode; }
    QStringList screenNames() const { return m_screenNames; }
    QScreen *targetScreen() const { return m_targetScreen; }
    bool followActiveScreen() const { return m_screenMode == QLatin1String("active"); }
    int reminderLeadMinutes() const { return m_reminderLeadMinutes; }
    bool postReminders() const { return m_postReminders; }

    void setAlignment(const QString &value);
    void setTopOffset(int value);
    void setScale(double value);
    void setOpacity(double value);
    void setAnimationDuration(int value);
    void setEasing(const QString &value);
    void setScreenMode(const QString &value);
    void setReminderLeadMinutes(int value);
    void setPostReminders(bool value);

public slots:
    // Restore every knob to its default and persist immediately.
    void reset();
    // Persist immediately, cancelling a pending debounced save. The customize
    // page calls it when an interaction ends, so a change can never be lost to
    // the debounce window.
    void flush();

signals:
    void alignmentChanged();
    void topOffsetChanged();
    void scaleChanged();
    void opacityChanged();
    void animationDurationChanged();
    void easingChanged();
    void screenModeChanged();
    void screenNamesChanged();
    void targetScreenChanged();
    void followActiveScreenChanged();
    void reminderLeadMinutesChanged();
    void postRemindersChanged();

private slots:
    // Re-read the screen list and re-resolve the target after a hotplug, a
    // monitor change or a change of the primary screen.
    void refreshScreens();

private:
    void load();
    void save();
    void scheduleSave();
    QScreen *resolveScreen() const;

    QString m_alignment = QStringLiteral("center");
    int m_topOffset = 6;
    double m_scale = 1.0;
    double m_opacity = 0.92;
    int m_animationDuration = 300;
    QString m_easing = QStringLiteral("back");
    QString m_screenMode = QStringLiteral("default");
    int m_reminderLeadMinutes = 10;
    bool m_postReminders = true;

    QStringList m_screenNames;
    QScreen *m_targetScreen = nullptr;
    QString m_settingsPath;
    QTimer m_saveTimer;
};
