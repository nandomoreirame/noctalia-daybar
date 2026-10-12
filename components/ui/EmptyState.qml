import QtQuick 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets

// Centered empty state: dim icon, title, optional description and an optional
// primary action. Fills the space it is given; leave actionText empty for none.
Item {
  id: root

  property string icon: ""
  property string title: ""
  property string description: ""
  property string actionText: ""
  property string actionIcon: ""
  signal action

  Layout.fillWidth: true
  Layout.fillHeight: true

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - Math.round(24 * Style.uiScaleRatio), Math.round(360 * Style.uiScaleRatio))
    spacing: Math.round(8 * Style.uiScaleRatio)

    NIcon {
      visible: root.icon !== ""
      Layout.alignment: Qt.AlignHCenter
      icon: root.icon
      pointSize: Style.fontSizeXXL
      color: Qt.alpha(Color.mOnSurface, 0.42)
    }

    NText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.title
      pointSize: Style.fontSizeM
      font.weight: Style.fontWeightSemiBold
      color: Color.mOnSurface
    }

    NText {
      visible: root.description !== ""
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.description
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }

    PillButton {
      visible: root.actionText !== ""
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: Math.round(4 * Style.uiScaleRatio)
      implicitHeight: Math.round(32 * Style.uiScaleRatio)
      primary: true
      icon: root.actionIcon
      text: root.actionText
      onClicked: root.action()
    }
  }
}
