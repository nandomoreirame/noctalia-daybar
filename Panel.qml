import QtQuick 6.11
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "components"
import "components/ui"
import "utils/tabs.js" as Tabs
import "utils/today.js" as Today

// Bar toolbar: Calendar, Today, Focus, Bookmarks and Notes tabs plus the Capture button.
Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  readonly property var mainInstance: pluginApi?.mainInstance ?? null
  readonly property var tabKeys: Tabs.TABS

  // Tab label with its count: done/total for Calendar and Today, size for the lists.
  function tabLabel(key) {
    const label = tr("tabs." + key);
    const m = mainInstance;
    if (!m)
      return label;
    if (key === "calendar")
      return Today.withProgress(label, m.calendarProgress);
    if (key === "today")
      return Today.withProgress(label, m.todayProgress);
    if (key === "bookmarks")
      return Today.withCount(label, (m.data.bookmarks || []).length);
    if (key === "notes")
      return Today.withCount(label, (m.data.notes || []).length);
    return label;
  }

  property real contentPreferredWidth: 680 * Style.uiScaleRatio
  property real contentPreferredHeight: 450 * Style.uiScaleRatio
  property bool initialTabApplied: false

  anchors.fill: parent

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  // An IPC `open <tab>` wins over the configured initial tab ("last" by default), once.
  // onMainInstanceChanged runs before the tab bar exists and again from
  // onCompleted; consuming the request on the first call made the second
  // call fall back to the initial tab.
  function pickInitialTab() {
    if (!mainInstance || !tabBar)
      return;
    const requested = mainInstance.requestedTab;
    if (initialTabApplied && requested === "")
      return;
    const key = Tabs.initialTab(requested, mainInstance.setting("initialTab"), mainInstance.data.ui?.lastTab);
    tabBar.currentIndex = tabKeys.indexOf(key);
    initialTabApplied = true;
    if (requested !== "") {
      // A tab opened by IPC counts as visited.
      mainInstance.setLastTab(key);
      mainInstance.requestedTab = "";
    }
  }

  onMainInstanceChanged: pickInitialTab()
  Component.onCompleted: pickInitialTab()

  Connections {
    target: root.mainInstance
    function onRequestedTabChanged() {
      if (root.mainInstance && root.mainInstance.requestedTab !== "")
        root.pickInitialTab();
    }
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Math.round(10 * Style.uiScaleRatio)
      spacing: Math.round(8 * Style.uiScaleRatio)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        IconTabs {
          id: tabBar
          model: root.tabKeys.map(k => ({ key: k, icon: Tabs.ICONS[k], label: root.tabLabel(k) }))
          // Remembered once the initial tab is in place, so opening never overwrites it.
          onCurrentIndexChanged: if (root.initialTabApplied && root.mainInstance) root.mainInstance.setLastTab(root.tabKeys[currentIndex])
        }

        Item {
          Layout.fillWidth: true
        }

        PillButton {
          icon: "refresh"
          busy: root.mainInstance?.syncing ?? false
          enabled: !busy
          tooltipText: root.tr("tabs.reload")
          onClicked: root.mainInstance?.refreshCalendar()
        }

        PillButton {
          icon: "bolt"
          text: root.tr("tabs.capture")
          // Close on the screen the panel opened on (the cursor may be elsewhere),
          // then open the overlay.
          onClicked: {
            if (root.pluginApi)
              root.pluginApi.closePanel(root.pluginApi.panelOpenScreen);
            if (root.mainInstance)
              root.mainInstance.openCapture();
          }
        }
      }

      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabBar.currentIndex

        CalendarView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        TodayView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        FocusView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        BookmarksView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        NotesView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }
      }
    }
  }
}
