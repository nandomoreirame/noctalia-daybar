import QtQuick 6.11
import Quickshell
import qs.Commons
import "components"

// Detached clock as a real Niri window titled "Daybar timer": move, resize, other
// monitor. Placement belongs to a niri window-rule matched by the title (README).
FloatingWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null

  title: "Daybar timer"
  implicitWidth: Math.round(280 * Style.uiScaleRatio)
  implicitHeight: Math.round(280 * Style.uiScaleRatio)
  minimumSize: Qt.size(Math.round(160 * Style.uiScaleRatio), Math.round(160 * Style.uiScaleRatio))
  visible: false
  color: Color.mSurface

  // Closed by the compositor (Mod+Q) or the Focus button: record it once.
  onVisibleChanged: {
    if (!visible && mainInstance?.clockWindowOpen)
      mainInstance.setClockWindow(false);
  }

  // Built only while shown: a face created with Main itself would bind to a
  // half-initialized pomodoro config (binding loop), and a hidden one would tick.
  Loader {
    anchors.fill: parent
    anchors.margins: Math.round(16 * Style.uiScaleRatio)
    active: root.visible
    sourceComponent: ClockFace {
      pluginApi: root.pluginApi
      mainInstance: root.mainInstance
    }
  }
}
