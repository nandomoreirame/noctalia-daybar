import QtQuick 6.11
import qs.Commons
import qs.Widgets

// Round checkbox: an outlined ring that fills with the accent when checked.
Rectangle {
  id: root

  property bool checked: false
  property string label: ""
  signal toggled

  implicitWidth: Math.round(16 * Style.uiScaleRatio)
  implicitHeight: implicitWidth
  radius: width / 2
  color: checked ? Color.mPrimary : "transparent"
  border.color: checked ? Color.mPrimary : Qt.alpha(Color.mOnSurface, activeFocus || mouse.containsMouse ? 0.6 : 0.3)
  border.width: Math.max(1, Math.round(1.5 * Style.uiScaleRatio))

  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.checked: checked
  Keys.onSpacePressed: toggled()

  NIcon {
    anchors.centerIn: parent
    visible: root.checked
    icon: "check"
    pointSize: Style.fontSizeXS
    color: Color.mOnPrimary
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -4
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
