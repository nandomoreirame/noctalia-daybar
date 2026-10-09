import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import "utils/pomodoro.js" as Pomodoro

// Bar entry: an icon, plus the focus clock while a pomodoro is running.
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
  readonly property bool barIsVertical: (Settings.data.bar.position || "top") === "left" || Settings.data.bar.position === "right"

  implicitWidth: barIsVertical || !timerVisible ? Style.capsuleHeight : contentRow.implicitWidth + Style.marginM * 2
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
        icon: root.timerVisible ? "brain" : "layout-list"
        applyUiScale: false
        color: root.timerVisible ? Color.mPrimary : (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)
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

    onClicked: mouse => {
      if (mouse.button === Qt.MiddleButton && root.mainInstance) {
        root.mainInstance.pomodoroRunning ? root.mainInstance.pomodoroPause() : root.mainInstance.pomodoroStart();
      } else if (root.pluginApi) {
        root.pluginApi.togglePanel(root.screen, root);
      }
    }
  }
}
