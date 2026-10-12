import QtQuick 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/pomodoro.js" as Pomodoro
import "../utils/clock.js" as Clock

// Detached clock face: the active clock's ring and numbers, sized by the host.
// Play/pause, reset (and close, when the host asks) fade in while the pointer is over it.
Item {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property bool showClose: false
  // Mode chips (Foco, Pausa curta, Pausa longa, Timer) under the controls; the window
  // turns them on, and they show only when the ring is wide enough.
  property bool showModes: false
  readonly property var modes: [["work", Pomodoro.WORK], ["short", Pomodoro.SHORT], ["long", Pomodoro.LONG], ["timer", Clock.TIMER_CHIP]]
  readonly property bool modesFit: ring.width >= Math.round(360 * Style.uiScaleRatio)
  property string closeText: ""
  signal closeRequested

  readonly property bool running: mainInstance?.shownRunning ?? false
  readonly property bool ringing: mainInstance?.shownRinging ?? false
  readonly property int remaining: mainInstance?.shownRemaining ?? 0
  readonly property bool hovered: hover.hovered
  readonly property string toggleText: ringing ? tr("capture.timer.dismiss") : (running ? tr("focus.pause") : tr("focus.start"))
  // The small pinned clock has no room for the labelled pill.
  readonly property bool compact: ring.width < Math.round(200 * Style.uiScaleRatio)

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  HoverHandler {
    id: hover
  }

  ProgressRing {
    id: ring
    anchors.centerIn: parent
    width: Math.min(root.width, root.height)
    height: width
    thickness: Math.max(3, Math.round(width * 0.02))
    progress: Clock.progress(root.remaining, root.mainInstance?.shownTotal ?? 0)
    arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
    accessibleName: Pomodoro.formatClock(root.remaining)

    NText {
      anchors.centerIn: parent
      // On a small ring the controls take the numbers' place while hovered.
      opacity: root.hovered && root.compact ? 0 : 1
      width: Math.round(ring.width * 0.8)
      horizontalAlignment: Text.AlignHCenter
      fontSizeMode: Text.HorizontalFit
      minimumPointSize: Style.fontSizeXS
      elide: Text.ElideNone
      text: Pomodoro.formatClock(root.remaining)
      family: Settings.data.ui.fontFixed
      // Upper bound only: HorizontalFit shrinks it to the ring width.
      pointSize: Style.fontSizeXXXL * 6
      font.weight: Style.fontWeightBold
      color: root.running ? Color.mPrimary : Color.mOnSurface
    }

    // Floats below the numbers on a large ring (they stay centered); over them, numbers
    // hidden, on a small one.
    ColumnLayout {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: root.compact ? parent.verticalCenter : undefined
      anchors.bottom: root.compact ? undefined : parent.bottom
      anchors.bottomMargin: Math.round(ring.height * (root.showModes && root.modesFit ? 0.12 : 0.2))
      spacing: Math.round(22 * Style.uiScaleRatio)
      opacity: root.hovered ? 1 : 0
      visible: opacity > 0

      Behavior on opacity {
        NumberAnimation {
          duration: 150
        }
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Math.round((root.compact ? 4 : 8) * Style.uiScaleRatio)

        PillButton {
          icon: "refresh"
          tooltipText: root.tr("focus.reset")
          onClicked: root.mainInstance.shownReset()
        }

        // Same pill as the Focus tab; icon only when the ring is too small for the label.
        PillButton {
          primary: true
          implicitHeight: Math.round((root.compact ? 28 : 34) * Style.uiScaleRatio)
          icon: root.ringing ? "bell-off" : (root.running ? "player-pause" : "player-play")
          text: root.compact ? "" : root.toggleText
          tooltipText: root.toggleText
          onClicked: root.mainInstance.shownToggle()
        }

        PillButton {
          visible: root.showClose
          icon: "x"
          tooltipText: root.closeText
          onClicked: root.closeRequested()
        }
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        visible: root.showModes && root.modesFit
        spacing: Math.round(4 * Style.uiScaleRatio)

        Repeater {
          model: root.modes

          Chip {
            required property var modelData
            text: root.tr("focus.mode." + modelData[0])
            selected: root.mainInstance?.shownClock === "timer" ? modelData[1] === Clock.TIMER_CHIP : root.mainInstance?.pomodoroMode === modelData[1]
            onClicked: root.mainInstance.selectFocusChip(modelData[1])
          }
        }
      }
    }
  }
}
