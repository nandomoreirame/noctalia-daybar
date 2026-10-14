import QtQuick 6.11
import QtQuick.Layouts 6.11
import QtQuick.Window 6.11
import qs.Commons

// List line with a soft hover wash. Children go into the inner RowLayout.
// A clickable row (Enter/Space too) can open `detail` below the line when expanded.
Rectangle {
  id: root

  default property alias content: row.data
  readonly property bool hovered: hover.hovered
  property bool clickable: false
  property bool expanded: false
  property Component detail: null
  property string accessibleName: ""
  signal clicked
  // True when the active focus item is this row or one of its descendants
  // (action buttons, inline editors). Views use it with hover/asking to keep
  // row actions visible for keyboard users.
  readonly property bool focusInside: {
    let f = Window.activeFocusItem;
    while (f) {
      if (f === root)
        return true;
      f = f.parent;
    }
    return false;
  }
  readonly property real lineHeight: Math.max(Math.round(30 * Style.uiScaleRatio), row.implicitHeight + Math.round(8 * Style.uiScaleRatio))

  Layout.fillWidth: true
  implicitHeight: lineHeight + (detailLoader.active ? detailLoader.implicitHeight + Math.round(8 * Style.uiScaleRatio) : 0)
  radius: Math.round(8 * Style.uiScaleRatio)
  color: hovered || expanded ? Qt.alpha(Color.mOnSurface, 0.04) : "transparent"
  border.color: activeFocus ? Qt.alpha(Color.mOnSurface, 0.4) : "transparent"
  border.width: Style.borderS

  activeFocusOnTab: clickable
  Accessible.role: clickable ? Accessible.Button : Accessible.ListItem
  Accessible.name: accessibleName
  Keys.onReturnPressed: if (clickable) root.clicked()
  Keys.onSpacePressed: if (clickable) root.clicked()

  HoverHandler {
    id: hover
  }

  // Below the row's children, so their own buttons keep their clicks.
  MouseArea {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.lineHeight
    enabled: root.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.lineHeight
    anchors.leftMargin: Math.round(6 * Style.uiScaleRatio)
    anchors.rightMargin: Math.round(6 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)
  }

  Loader {
    id: detailLoader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: row.bottom
    anchors.leftMargin: Math.round(6 * Style.uiScaleRatio)
    anchors.rightMargin: Math.round(6 * Style.uiScaleRatio)
    active: root.expanded && root.detail !== null
    sourceComponent: root.detail
  }
}
