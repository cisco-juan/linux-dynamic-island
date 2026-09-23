#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// Captures desktop notifications by parsing the stdout of a long-running
// `dbus-monitor "interface='org.freedesktop.Notifications'"` subprocess.
//
// This is deliberately a passive observer: it never replies to any D-Bus
// message, so it cannot interfere with the real notification daemon. The
// subprocess is restarted automatically if it exits.
class NotificationMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)

public:
    explicit NotificationMonitor(QObject *parent = nullptr);

    bool running() const { return m_process.state() == QProcess::Running; }

signals:
    void notificationReceived(const QVariantMap &notification);
    void notificationClosed(uint id);
    void actionInvoked(uint id, const QString &action);
    void runningChanged();

private slots:
    void onReadyRead();
    void startMonitor();
    void onProcessFinished(int exitCode, QProcess::ExitStatus status);

private:
    enum State {
        Idle,
        Notify,
        Closed,
        Action,
    };

    void processLine(const QString &line);
    void resetParseState();
    void finishNotify();
    void parseHints();

    // dbus-monitor prints a string value containing a newline across several
    // physical lines. These helpers buffer such a value until its closing quote
    // arrives, then re-dispatch the joined logical line.
    void beginQuotedValue(const QString &line);
    void continueQuotedValue(const QString &line);

    static QString parseQuoted(const QString &line);
    static QString stripQuoted(const QString &line);
    static int bracketDelta(const QString &line);
    static int firstUnescapedQuote(const QString &line);
    static int unescapedQuoteCount(const QString &line);

    QProcess m_process;
    QByteArray m_buffer;

    State m_state = Idle;
    int m_field = 0;
    QVariantMap m_pending;

    bool m_inArray = false;
    int m_arrayDepth = 0;
    int m_arrayField = -1;
    QStringList m_arrayLines;

    bool m_inString = false;
    QString m_stringPrefix;
    QString m_stringRaw;
};
