import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "utils/pomodoro.js" as Pomodoro
import "utils/tabs.js" as Tabs
import "utils/today.js" as Today

// Bar entry: the next tab's icon and label, or the focus clock while a pomodoro is running.
// Left click toggles the toolbar, middle click starts/pauses the timer.
Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance ?? null
  readonly property bool timerVisible: !!mainInstance && (mainInstance.pomodoroRunning || mainInstance.pomodoroSoundPlaying)
  // Tab the panel will open on, so the bar tells where a click lands.
  readonly property string nextTab: mainInstance ? Tabs.initialTab("", mainInstance.setting("initialTab"), mainInstance.data.ui?.lastTab) : Tabs.FALLBACK
  readonly property string nextTabIcon: Tabs.ICONS[nextTab]
  readonly property var nextTabProgress: !mainInstance ? null : nextTab === "today" ? mainInstance.todayProgress : nextTab === "calendar" ? mainInstance.calendarProgress : null
  // The Calendar tab shows today's next event instead of its name ("15:00 Reunião"),
  // or "Nada marcado para hoje." when nothing is left today.
  readonly property string upcomingText: {
    if (nextTab !== "calendar" || !mainInstance)
      return "";
    const ev = mainInstance.upcomingEvent;
    return ev ? ev.time + " " + ev.summary : pluginApi?.tr("calendar.nothing") ?? "";
  }
  readonly property bool labelIsEmpty: nextTab === "calendar" && !!mainInstance && !mainInstance.upcomingEvent
  readonly property string labelText: upcomingText !== "" ? upcomingText : Today.withProgress(pluginApi?.tr("tabs." + nextTab) ?? "", nextTabProgress)
  readonly property bool barIsVertical: (Settings.data.bar.position || "top") === "left" || Settings.data.bar.position === "right"

  implicitWidth: barIsVertical ? Style.capsuleHeight : contentRow.implicitWidth + Style.marginM * 2
  implicitHeight: Style.capsuleHeight

  Rectangle {
    anchors.centerIn: parent
    width: root.implicitWidth
    height: root.implicitHeight
    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NIcon {
        icon: root.timerVisible ? Tabs.ICONS.focus : root.nextTabIcon
        applyUiScale: false
        color: root.timerVisible ? Color.mPrimary : (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)
      }

      NText {
        visible: !root.timerVisible && !root.barIsVertical
        id: label
        text: root.labelText
        elide: Text.ElideRight
        Layout.maximumWidth: Math.round(220 * Style.uiScaleRatio)
        pointSize: Style.barFontSize
        font.weight: Style.fontWeightSemiBold
        color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
        // The empty-day message reads as a placeholder, not as an event.
        font.italic: root.labelIsEmpty
        opacity: root.labelIsEmpty ? 0.6 : 1
      }

      NText {
        visible: root.timerVisible && !root.barIsVertical
        text: Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)
        family: Settings.data.ui.fontFixed
        pointSize: Style.barFontSize
        color: Color.mPrimary
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    // Full text when the label is cut with "...".
    onEntered: if (label.visible && label.truncated) TooltipService.show(root, root.labelText, BarService.getTooltipDirection(root.screen?.name))
    onExited: TooltipService.hide(root)

    onClicked: mouse => {
      if (mouse.button === Qt.MiddleButton && root.mainInstance) {
        root.mainInstance.pomodoroRunning ? root.mainInstance.pomodoroPause() : root.mainInstance.pomodoroStart();
      } else if (root.pluginApi) {
        root.pluginApi.togglePanel(root.screen, root);
      }
    }
  }
}
