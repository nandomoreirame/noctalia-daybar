import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "components"

// Bar toolbar: Calendar, Today, Focus and Inbox tabs plus the Capture button.
Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  readonly property var mainInstance: pluginApi?.mainInstance ?? null
  readonly property var tabKeys: ["calendar", "today", "focus", "inbox"]

  property real contentPreferredWidth: 680 * Style.uiScaleRatio
  property real contentPreferredHeight: 380 * Style.uiScaleRatio
  property bool initialTabApplied: false

  anchors.fill: parent

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  // An IPC `open <tab>` wins over the configured initial tab, once.
  // onMainInstanceChanged runs before the tab bar exists and again from
  // onCompleted; consuming the request on the first call made the second
  // call fall back to the initial tab.
  function pickInitialTab() {
    if (!mainInstance || !tabBar)
      return;
    const requested = mainInstance.requestedTab;
    if (initialTabApplied && requested === "")
      return;
    const fallback = mainInstance.setting("initialTab");
    const index = tabKeys.indexOf(requested !== "" ? requested : fallback);
    tabBar.currentIndex = index >= 0 ? index : 1;
    initialTabApplied = true;
    if (requested !== "")
      mainInstance.requestedTab = "";
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
      anchors.margins: Style.marginM
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTabBar {
          id: tabBar
          Layout.fillWidth: true

          Repeater {
            model: root.tabKeys

            NTabButton {
              required property string modelData
              required property int index
              text: root.tr("tabs." + modelData)
              tabIndex: index
              checked: tabBar.currentIndex === index
            }
          }
        }

        NIconButton {
          icon: "bolt"
          tooltipText: root.tr("tabs.capture")
          onClicked: {
            if (root.mainInstance)
              root.mainInstance.openCapture();
            root.pluginApi?.withCurrentScreen(screen => root.pluginApi.closePanel(screen));
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

        InboxView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }
      }
    }
  }
}
