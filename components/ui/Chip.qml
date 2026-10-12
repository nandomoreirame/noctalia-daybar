import QtQuick 6.11
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Small selectable pill (type pickers, mode switches).
Rectangle {
  id: root

  property string text: ""
  property string icon: ""
  property bool selected: false
  signal clicked

  implicitHeight: Math.round(24 * Style.uiScaleRatio)
  implicitWidth: content.implicitWidth + Math.round(20 * Style.uiScaleRatio)
  radius: height / 2
  color: selected ? Qt.alpha(Color.mOnSurface, 0.12) : (mouse.containsMouse ? Qt.alpha(Color.mOnSurface, 0.05) : "transparent")
  border.color: activeFocus ? Qt.alpha(Color.mOnSurface, 0.4) : "transparent"
  border.width: Style.borderS

  activeFocusOnTab: true
  Accessible.role: Accessible.RadioButton
  Accessible.name: text
  Accessible.checked: selected
  Keys.onSpacePressed: clicked()
  Keys.onReturnPressed: clicked()

  readonly property color tint: selected ? Color.mOnSurface : Qt.alpha(Color.mOnSurface, mouse.containsMouse ? 0.75 : 0.56)

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: Math.round(5 * Style.uiScaleRatio)

    NIcon {
      visible: root.icon !== ""
      icon: root.icon
      pointSize: Style.fontSizeM
      color: root.tint
    }

    NText {
      text: root.text
      pointSize: Style.fontSizeS
      font.weight: root.selected ? Style.fontWeightSemiBold : Style.fontWeightRegular
      color: root.tint
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
