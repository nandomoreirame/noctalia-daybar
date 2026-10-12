import QtQuick 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets
import qs.Services.UI

// Pill button. `primary` inverts it (ink fill); without `text` it is a round icon
// button and `tooltipText` doubles as its accessible name.
Rectangle {
  id: root

  property string text: ""
  property string icon: ""
  property string tooltipText: ""
  property bool primary: false
  property bool danger: false
  // Spins the icon (e.g. while a sync runs).
  property bool busy: false
  signal clicked

  readonly property bool iconOnly: text === ""
  readonly property bool hovered: mouse.containsMouse

  implicitHeight: Math.round(28 * Style.uiScaleRatio)
  implicitWidth: iconOnly ? implicitHeight : row.implicitWidth + Math.round(24 * Style.uiScaleRatio)
  radius: height / 2
  opacity: enabled ? 1 : 0.4
  scale: mouse.pressed ? 0.94 : 1
  color: primary ? (hovered ? Color.mOnSurface : Qt.alpha(Color.mOnSurface, 0.92)) : Qt.alpha(Color.mOnSurface, hovered ? 0.15 : 0.09)
  border.color: activeFocus ? Qt.alpha(Color.mOnSurface, 0.4) : "transparent"
  border.width: Style.borderS

  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: text !== "" ? text : tooltipText
  Keys.onSpacePressed: clicked()
  Keys.onReturnPressed: clicked()

  Behavior on scale {
    NumberAnimation {
      duration: 80
    }
  }

  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: Math.round(6 * Style.uiScaleRatio)

    NIcon {
      id: iconItem
      visible: root.icon !== ""
      icon: root.icon
      pointSize: Style.fontSizeM
      color: root.primary ? Color.mSurface : (root.danger && root.hovered ? Color.mError : Qt.alpha(Color.mOnSurface, 0.92))
    }

    NText {
      visible: !root.iconOnly
      text: root.text
      pointSize: Style.fontSizeS
      font.weight: Style.fontWeightMedium
      color: root.primary ? Color.mSurface : Qt.alpha(Color.mOnSurface, 0.92)
    }
  }

  RotationAnimator {
    target: iconItem
    from: 0
    to: 360
    duration: 900
    loops: Animation.Infinite
    running: root.busy
    onRunningChanged: if (!running) iconItem.rotation = 0
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
    onEntered: if (root.iconOnly && root.tooltipText !== "") TooltipService.show(root, root.tooltipText)
    onExited: TooltipService.hide(root)
  }
}
