import QtQuick 6.11
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons

// List line with a soft hover wash. Children go into the inner RowLayout.
Rectangle {
  id: root

  default property alias content: row.data
  readonly property bool hovered: hover.hovered
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

  Layout.fillWidth: true
  implicitHeight: Math.max(Math.round(30 * Style.uiScaleRatio), row.implicitHeight + Math.round(8 * Style.uiScaleRatio))
  radius: Math.round(8 * Style.uiScaleRatio)
  color: hovered ? Qt.alpha(Color.mOnSurface, 0.04) : "transparent"

  HoverHandler {
    id: hover
  }

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Math.round(6 * Style.uiScaleRatio)
    anchors.rightMargin: Math.round(6 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)
  }
}
