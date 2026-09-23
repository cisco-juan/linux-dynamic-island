#include "notificationmonitor.h"

#include <QDBusArgument>
#include <QTimer>

#ifdef Q_OS_LINUX
#include <csignal>
#include <sys/prctl.h>
#endif

namespace {
constexpr auto kMatchRule = "interface='org.freedesktop.Notifications'";
}

NotificationMonitor::NotificationMonitor(QObject *parent)
    : QObject(parent)
{
    connect(&m_process, &QProcess::readyReadStandardOutput,
            this, &NotificationMonitor::onReadyRead);
    connect(&m_process, &QProcess::finished,
            this, &NotificationMonitor::onProcessFinished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            qWarning("dynamic-island: failed to start dbus-monitor; notifications disabled");
        }
    });

#ifdef Q_OS_LINUX
    // Ask the kernel to signal the child when this process dies. This covers
    // hard kills (SIGKILL), where run.sh's `pkill -P` can no longer match the
    // child because the parent is already gone.
    m_process.setChildProcessModifier([] {
        ::prctl(PR_SET_PDEATHSIG, SIGTERM);
    });
#endif

    startMonitor();
}

void NotificationMonitor::startMonitor()
{
    if (m_process.state() != QProcess::NotRunning)
        return;

    m_buffer.clear();
    resetParseState();

    m_process.start(QStringLiteral("dbus-monitor"), {QString::fromLatin1(kMatchRule)});
    emit runningChanged();
}

void NotificationMonitor::onProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    Q_UNUSED(exitCode)
    Q_UNUSED(status)
    emit runningChanged();
    // dbus-monitor should never exit on its own; restart it shortly.
    QTimer::singleShot(1000, this, &NotificationMonitor::startMonitor);
}

void NotificationMonitor::onReadyRead()
{
    m_buffer += m_process.readAllStandardOutput();

    int newline;
    while ((newline = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray raw = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);
        processLine(QString::fromUtf8(raw));
    }
}

void NotificationMonitor::resetParseState()
{
    m_state = Idle;
    m_field = 0;
    m_pending.clear();
    m_inArray = false;
    m_arrayDepth = 0;
    m_arrayField = -1;
    m_arrayLines.clear();
    m_inString = false;
    m_stringPrefix.clear();
    m_stringRaw.clear();
}

int NotificationMonitor::firstUnescapedQuote(const QString &line)
{
    bool escaped = false;
    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == QLatin1Char('\\')) {
            escaped = true;
            continue;
        }
        if (c == QLatin1Char('"'))
            return i;
    }
    return -1;
}

int NotificationMonitor::unescapedQuoteCount(const QString &line)
{
    int count = 0;
    bool escaped = false;
    for (const QChar c : line) {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == QLatin1Char('\\')) {
            escaped = true;
            continue;
        }
        if (c == QLatin1Char('"'))
            ++count;
    }
    return count;
}

void NotificationMonitor::beginQuotedValue(const QString &line)
{
    const int quote = firstUnescapedQuote(line);
    if (quote < 0) {
        // The caller only starts buffering when a quote is open.
        return;
    }
    m_stringPrefix = line.left(quote + 1);
    m_stringRaw = line.mid(quote + 1);
    m_inString = true;
}

void NotificationMonitor::continueQuotedValue(const QString &line)
{
    const int quote = firstUnescapedQuote(line);
    if (quote < 0) {
        // Still inside the string: the whole physical line is content.
        m_stringRaw += QLatin1Char('\n');
        m_stringRaw += line;
        return;
    }

    // Closing quote found: join the physical lines with a literal newline so
    // the parsed value keeps both lines, then re-dispatch as one logical line.
    m_stringRaw += QLatin1Char('\n');
    m_stringRaw += line.left(quote);

    const QString logical = m_stringPrefix + m_stringRaw + QLatin1Char('"')
                            + line.mid(quote + 1);
    m_inString = false;
    m_stringPrefix.clear();
    m_stringRaw.clear();
    processLine(logical);
}

QString NotificationMonitor::stripQuoted(const QString &line)
{
    QString out;
    out.reserve(line.size());
    bool inString = false;
    bool escaped = false;
    for (const QChar c : line) {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == QLatin1Char('\\')) {
            escaped = true;
            continue;
        }
        if (c == QLatin1Char('"')) {
            inString = !inString;
            continue;
        }
        if (!inString)
            out += c;
    }
    return out;
}

int NotificationMonitor::bracketDelta(const QString &line)
{
    int delta = 0;
    for (const QChar c : line) {
        if (c == QLatin1Char('['))
            ++delta;
        else if (c == QLatin1Char(']'))
            --delta;
    }
    return delta;
}

QString NotificationMonitor::parseQuoted(const QString &line)
{
    const int first = line.indexOf(QLatin1Char('"'));
    const int last = line.lastIndexOf(QLatin1Char('"'));
    if (first < 0 || last <= first)
        return QString();

    const QString raw = line.mid(first + 1, last - first - 1);
    QString out;
    out.reserve(raw.size());
    for (int i = 0; i < raw.size(); ++i) {
        const QChar c = raw.at(i);
        if (c == QLatin1Char('\\') && i + 1 < raw.size()) {
            const QChar next = raw.at(++i);
            if (next == QLatin1Char('n'))
                out += QLatin1Char('\n');
            else if (next == QLatin1Char('t'))
                out += QLatin1Char('\t');
            else if (next == QLatin1Char('r'))
                out += QLatin1Char('\r');
            else
                out += next;
        } else {
            out += c;
        }
    }
    return out;
}

void NotificationMonitor::parseHints()
{
    const QString joined = m_arrayLines.join(QLatin1Char('\n'));

    // urgency: `string "urgency"` followed by `variant byte N`
    const int urgencyPos = joined.indexOf(QStringLiteral("\"urgency\""));
    if (urgencyPos >= 0) {
        const int bytePos = joined.indexOf(QStringLiteral("byte "), urgencyPos);
        if (bytePos >= 0) {
            const QString rest = joined.mid(bytePos + 5);
            int end = 0;
            while (end < rest.size() && rest.at(end).isDigit())
                ++end;
            if (end > 0)
                m_pending.insert(QStringLiteral("urgency"), rest.left(end).toInt());
        }
    }

    // desktop-entry: the dict entry has the key (`string "desktop-entry"`) on
    // one line and its value (`variant string "..."`) on the next. Parse the
    // value within that single line only: `parseQuoted` uses lastIndexOf('"'),
    // so scanning the whole block would swallow every quoted hint that follows.
    int entryLine = -1;
    for (int i = 0; i < m_arrayLines.size(); ++i) {
        if (m_arrayLines.at(i).contains(QStringLiteral("\"desktop-entry\""))) {
            entryLine = i;
            break;
        }
    }
    if (entryLine >= 0) {
        for (int i = entryLine + 1; i < m_arrayLines.size(); ++i) {
            const QString &line = m_arrayLines.at(i);
            if (line.contains(QStringLiteral("string \""))) {
                const QString value = parseQuoted(line);
                if (!value.isEmpty())
                    m_pending.insert(QStringLiteral("desktopEntry"), value);
                break;
            }
        }
    }

    // image-path: same two-line shape as desktop-entry. `notify-send -i` and
    // many real apps put the icon here instead of the app_icon field.
    int imageLine = -1;
    for (int i = 0; i < m_arrayLines.size(); ++i) {
        if (m_arrayLines.at(i).contains(QStringLiteral("\"image-path\""))) {
            imageLine = i;
            break;
        }
    }
    if (imageLine >= 0) {
        for (int i = imageLine + 1; i < m_arrayLines.size(); ++i) {
            const QString &line = m_arrayLines.at(i);
            if (line.contains(QStringLiteral("string \""))) {
                const QString value = parseQuoted(line);
                if (!value.isEmpty())
                    m_pending.insert(QStringLiteral("imagePath"), value);
                break;
            }
        }
    }
}

void NotificationMonitor::finishNotify()
{
    emit notificationReceived(m_pending);
    resetParseState();
}

void NotificationMonitor::processLine(const QString &line)
{
    const QString trimmed = line.trimmed();
    if (trimmed.isEmpty())
        return;

    // While a multi-line quoted value is open, every physical line is raw
    // string content: never interpret it as a field, array, or dict entry.
    if (m_inString) {
        continueQuotedValue(line);
        return;
    }

    const bool isHeader = trimmed.startsWith(QLatin1String("method call"))
                          || trimmed.startsWith(QLatin1String("method return"))
                          || trimmed.startsWith(QLatin1String("signal"))
                          || trimmed.startsWith(QLatin1String("error"));

    if (isHeader) {
        if (trimmed.startsWith(QLatin1String("method call"))
            && trimmed.contains(QLatin1String("member=Notify"))) {
            resetParseState();
            m_state = Notify;
        } else if (trimmed.contains(QLatin1String("member=NotificationClosed"))) {
            resetParseState();
            m_state = Closed;
        } else if (trimmed.contains(QLatin1String("member=ActionInvoked"))) {
            resetParseState();
            m_state = Action;
        } else {
            resetParseState();
        }
        return;
    }

    // An odd number of unescaped quotes means the string is unterminated and
    // continues on the next physical line.
    if (unescapedQuoteCount(trimmed) % 2 == 1) {
        beginQuotedValue(trimmed);
        return;
    }

    switch (m_state) {
    case Idle:
        return;

    case Notify: {
        // Arrays (actions, then hints) need bracket-aware consumption.
        if (m_field == 5 || m_field == 6) {
            if (!m_inArray) {
                m_inArray = true;
                m_arrayField = m_field;
                m_arrayDepth = 0;
                m_arrayLines.clear();
            }
            if (m_arrayField == 6)
                m_arrayLines << trimmed;
            m_arrayDepth += bracketDelta(stripQuoted(trimmed));
            if (m_arrayDepth <= 0) {
                if (m_arrayField == 6)
                    parseHints();
                m_inArray = false;
                ++m_field;
            }
            return;
        }

        switch (m_field) {
        case 0: // app_name
            m_pending.insert(QStringLiteral("appName"), parseQuoted(trimmed));
            break;
        case 1: // replaces_id (also the notification id)
            m_pending.insert(QStringLiteral("id"), trimmed.section(QLatin1Char(' '), -1).toUInt());
            break;
        case 2: // app_icon
            m_pending.insert(QStringLiteral("appIcon"), parseQuoted(trimmed));
            break;
        case 3: // summary
            m_pending.insert(QStringLiteral("summary"), parseQuoted(trimmed));
            break;
        case 4: // body
            m_pending.insert(QStringLiteral("body"), parseQuoted(trimmed));
            break;
        case 7: // expire_timeout
            m_pending.insert(QStringLiteral("expireTimeout"), trimmed.section(QLatin1Char(' '), -1).toInt());
            if (!m_pending.contains(QStringLiteral("urgency")))
                m_pending.insert(QStringLiteral("urgency"), 1);
            finishNotify();
            return;
        default:
            break;
        }
        ++m_field;
        return;
    }

    case Closed: {
        if (m_field == 0) {
            m_pending.insert(QStringLiteral("id"), trimmed.section(QLatin1Char(' '), -1).toUInt());
            ++m_field;
        } else if (m_field == 1) {
            emit notificationClosed(m_pending.value(QStringLiteral("id")).toUInt());
            resetParseState();
        }
        return;
    }

    case Action: {
        if (m_field == 0) {
            m_pending.insert(QStringLiteral("id"), trimmed.section(QLatin1Char(' '), -1).toUInt());
            ++m_field;
        } else if (m_field == 1) {
            emit actionInvoked(m_pending.value(QStringLiteral("id")).toUInt(), parseQuoted(trimmed));
            resetParseState();
        }
        return;
    }
    }
}
