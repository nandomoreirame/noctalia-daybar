import QtQuick 6.11
import QtQuick.Layouts
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
  property string closeText: ""
  signal closeRequested

  readonly property bool running: mainInstance?.shownRunning ?? false
  readonly property bool ringing: mainInstance?.shownRinging ?? false
  readonly property int remaining: mainInstance?.shownRemaining ?? 0
  readonly property bool hovered: hover.hovered
  // Buttons scale with the ring, so the small overlay keeps them inside it.
  readonly property int buttonSize: Math.max(18, Math.round(ring.width * 0.17))

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
    thickness: Math.max(3, Math.round(width * 0.04))
    progress: Clock.progress(root.remaining, root.mainInstance?.shownTotal ?? 0)
    arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
    accessibleName: Pomodoro.formatClock(root.remaining)

    NText {
      anchors.centerIn: parent
      // Moves up while the controls show, so they never cover the numbers.
      anchors.verticalCenterOffset: root.hovered ? -Math.round(ring.height * 0.1) : 0
      width: Math.round(ring.width * 0.66)
      horizontalAlignment: Text.AlignHCenter
      fontSizeMode: Text.HorizontalFit
      minimumPointSize: Style.fontSizeXS
      elide: Text.ElideNone
      text: Pomodoro.formatClock(root.remaining)
      family: Settings.data.ui.fontFixed
      // Upper bound only: HorizontalFit shrinks it to the ring width.
      pointSize: Style.fontSizeXXXL * 4
      font.weight: Style.fontWeightBold
      color: root.running ? Color.mPrimary : Color.mOnSurface

      Behavior on anchors.verticalCenterOffset {
        NumberAnimation {
          duration: 150
        }
      }
    }

    RowLayout {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round(ring.height * 0.17)
      spacing: Math.round(4 * Style.uiScaleRatio)
      opacity: root.hovered ? 1 : 0
      visible: opacity > 0

      Behavior on opacity {
        NumberAnimation {
          duration: 150
        }
      }

      PillButton {
        implicitHeight: root.buttonSize
        icon: root.ringing ? "bell-off" : (root.running ? "player-pause" : "player-play")
        tooltipText: root.ringing ? root.tr("capture.timer.dismiss") : (root.running ? root.tr("focus.pause") : root.tr("focus.start"))
        onClicked: root.mainInstance.shownToggle()
      }

      PillButton {
        implicitHeight: root.buttonSize
        icon: "refresh"
        tooltipText: root.tr("focus.reset")
        onClicked: root.mainInstance.shownReset()
      }

      PillButton {
        visible: root.showClose
        implicitHeight: root.buttonSize
        icon: "x"
        tooltipText: root.closeText
        onClicked: root.closeRequested()
      }
    }
  }
}
