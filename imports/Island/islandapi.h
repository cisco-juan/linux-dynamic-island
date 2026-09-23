#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// D-Bus service that lets other applications drive the island and discover its
// live state, plus the on-disk custom-widget registry.
//
// The object is exported on the session bus as
//   bus name:  io.github.cisco_juan.DynamicIsland
//   path:      /Island
//   interface: io.github.cisco_juan.DynamicIsland
//
// The API never touches the UI directly. Methods only emit request signals that
// the QML bridge in `main.qml` fulfils, and the island writes its live state
// back into the `mode`/`page`/`expanded`/`widget` properties so `GetStatus()`
// and the state-change signals stay truthful.
//
// Graceful degradation: when the session bus is unavailable, or the well-known
// name is already owned by another instance, the constructor logs once and the
// object keeps working as an internal registry with no D-Bus presence. It never
// blocks the UI and never crashes.
//
// The instance is intentionally leaked: it must outlive every QML engine. The
// plugin registers it as a singleton through a provider and pins CppOwnership.
class IslandApi : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.cisco_juan.DynamicIsland")

    // Constant interface version. The property name keeps its capital letter so
    // the D-Bus property reads as `Version`.
    Q_PROPERTY(uint Version READ version CONSTANT)
    // Live island state, written back by QML. The NOTIFY signals become D-Bus
    // property-change signals; the dedicated `ExpansionChanged`/`PageChanged`/
    // `WidgetShown` signals below are emitted from the same setters.
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(QString page READ page WRITE setPage NOTIFY pageChanged)
    Q_PROPERTY(bool expanded READ expanded WRITE setExpanded NOTIFY expandedChanged)
    Q_PROPERTY(QString widget READ widget WRITE setWidget NOTIFY widgetChanged)
    // Discovered custom widgets (read-only). `widgetsRevision` changes on every
    // rescan so a QML Loader can force a reload.
    Q_PROPERTY(QStringList widgets READ widgets NOTIFY widgetsChanged)
    Q_PROPERTY(QVariantList widgetList READ widgetList NOTIFY widgetsChanged)
    Q_PROPERTY(int widgetsRevision READ widgetsRevision NOTIFY widgetsChanged)

public:
    explicit IslandApi(QObject *parent = nullptr);
    ~IslandApi() override;

    // The process-wide instance backing the QML singleton.
    static IslandApi *instance();

    uint version() const { return 1; }
    QString mode() const { return m_mode; }
    QString page() const { return m_page; }
    bool expanded() const { return m_expanded; }
    QString widget() const { return m_widget; }
    QStringList widgets() const { return m_widgets; }
    QVariantList widgetList() const { return m_widgetInfos; }
    int widgetsRevision() const { return m_widgetsRevision; }

    void setMode(const QString &value);
    void setPage(const QString &value);
    void setExpanded(bool value);
    void setWidget(const QString &value);

    // ---- QML-only helpers -------------------------------------------------
    // Declared Q_INVOKABLE on purpose: QDBusConnection::ExportAllSlots exports
    // `public slots` only, not Q_INVOKABLE methods (verified empirically), so
    // these stay off the D-Bus interface and the introspection output matches
    // docs/api.md exactly.
    //
    // Push the pages the island currently offers so ListPages() reports them.
    Q_INVOKABLE void setAvailablePages(const QStringList &pages);
    // Called by the bridge when a card is actually displayed / dismissed.
    Q_INVOKABLE void reportCardShown(uint id, const QString &appName, const QString &title);
    Q_INVOKABLE void reportCardDismissed(uint id);
    // Absolute path of a widget's entry point, for the Loader's `source`.
    Q_INVOKABLE QString widgetSource(const QString &widgetId) const;
    Q_INVOKABLE QString widgetName(const QString &widgetId) const;
    Q_INVOKABLE QString widgetIcon(const QString &widgetId) const;

public slots:
    // Allocate an id synchronously and ask the island to show a card.
    uint ShowCard(const QString &appName, const QString &title, const QString &body,
                  const QString &icon, int urgency, int timeoutMs);
    void DismissCard(uint id);
    void DismissAll();
    void Expand();
    void Collapse();
    void Toggle();
    void ShowPage(const QString &pageId);
    QStringList ListPages() const;
    void ShowWidget(const QString &widgetId);
    void HideWidget();
    QStringList ListWidgets() const;
    void ReloadWidgets();
    QVariantMap GetStatus() const;

signals:
    // Requests fulfilled by the QML bridge.
    void cardRequested(uint id, const QString &appName, const QString &title,
                       const QString &body, const QString &icon, int urgency, int timeoutMs);
    void cardDismissRequested(uint id);
    void dismissAllRequested();
    void expandRequested(bool expanded);
    void pageRequested(const QString &pageId);
    void widgetRequested(const QString &widgetId);
    void hideWidgetRequested();

    // Public notifications emitted once the island has actually changed.
    void CardShown(uint id, const QString &appName, const QString &title);
    void CardDismissed(uint id);
    void ExpansionChanged(bool expanded);
    void PageChanged(const QString &pageId);
    void WidgetShown(const QString &widgetId);

    // Property NOTIFY signals (also exported on D-Bus).
    void modeChanged();
    void pageChanged();
    void expandedChanged();
    void widgetChanged();
    void widgetsChanged();

private:
    void registerOnBus();
    void scanWidgets();

    bool m_serviceAvailable = false;
    uint m_nextCardId = 1;

    QString m_mode = QStringLiteral("idle");
    QString m_page;
    bool m_expanded = false;
    QString m_widget;
    QStringList m_pages;

    QStringList m_widgets;
    QVariantList m_widgetInfos;
    int m_widgetsRevision = 0;
};
