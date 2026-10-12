import QtQuick 6.11
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "components"
import "utils/clock.js" as Clock

// Detached clock pinned to a screen corner. Top layer (full-screen apps cover it),
// never takes keyboard focus, reserves no space but stays clear of the bar.
PanelWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  readonly property var corner: Clock.cornerAnchors(mainInstance?.setting("clockCorner"))
  readonly property int ringPx: Math.round(Clock.ringSize(mainInstance?.setting("clockSize")) * Style.uiScaleRatio)
  readonly property int pad: Math.round(8 * Style.uiScaleRatio)

  anchors.top: corner.top
  anchors.bottom: corner.bottom
  anchors.left: corner.left
  anchors.right: corner.right
  margins.top: Style.marginL
  margins.bottom: Style.marginL
  margins.left: Style.marginL
  margins.right: Style.marginL
  implicitWidth: ringPx + pad * 2
  implicitHeight: implicitWidth
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-daybar-clock"
  WlrLayershell.exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  function openOn(targetScreen) {
    screen = targetScreen;
    visible = true;
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.alpha(Color.mSurface, 0.88)
    border.color: Qt.alpha(Color.mOnSurface, 0.08)
    border.width: Style.borderS
  }

  // Built only while shown (see ClockWindow).
  Loader {
    anchors.fill: parent
    anchors.margins: root.pad
    active: root.visible
    sourceComponent: ClockFace {
      pluginApi: root.pluginApi
      mainInstance: root.mainInstance
      showClose: true
      closeText: root.pluginApi ? root.pluginApi.tr("focus.clock-overlay-close") : ""
      onCloseRequested: root.mainInstance.setClockOverlay(false)
    }
  }
}
