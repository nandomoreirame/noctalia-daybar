import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Icon tabs: inactive tabs show only the icon, the active one grows into a
// pill with its label. model: [{ key, icon, label }]
RowLayout {
  id: root

  property var model: []
  property int currentIndex: 0

  spacing: Math.round(4 * Style.uiScaleRatio)

  Repeater {
    model: root.model

    Rectangle {
      id: tab
      required property var modelData
      required property int index
      readonly property bool active: root.currentIndex === index
      readonly property bool hovered: mouse.containsMouse

      implicitHeight: Math.round(26 * Style.uiScaleRatio)
      implicitWidth: active ? content.implicitWidth + Math.round(20 * Style.uiScaleRatio) : Math.round(32 * Style.uiScaleRatio)
      radius: height / 2
      color: active ? Qt.alpha(Color.mOnSurface, 0.1) : (hovered ? Qt.alpha(Color.mOnSurface, 0.07) : "transparent")
      border.color: activeFocus ? Qt.alpha(Color.mOnSurface, 0.4) : "transparent"
      border.width: Style.borderS
      clip: true

      activeFocusOnTab: true
      Accessible.role: Accessible.PageTab
      Accessible.name: modelData.label
      Accessible.selected: active
      Keys.onSpacePressed: root.currentIndex = index
      Keys.onReturnPressed: root.currentIndex = index
      Keys.onLeftPressed: root.currentIndex = Math.max(0, root.currentIndex - 1)
      Keys.onRightPressed: root.currentIndex = Math.min(root.model.length - 1, root.currentIndex + 1)

      Behavior on implicitWidth {
        NumberAnimation {
          duration: 160
          easing.type: Easing.OutCubic
        }
      }

      RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Math.round(6 * Style.uiScaleRatio)

        NIcon {
          icon: tab.modelData.icon
          pointSize: Style.fontSizeL
          color: tab.active ? Color.mOnSurface : Qt.alpha(Color.mOnSurface, tab.hovered ? 0.75 : 0.56)
        }

        NText {
          visible: tab.active
          text: tab.modelData.label
          pointSize: Style.fontSizeS
          font.weight: Style.fontWeightSemiBold
          color: Color.mOnSurface
        }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.currentIndex = tab.index
      }
    }
  }
}
