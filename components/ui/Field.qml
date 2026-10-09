import QtQuick
import QtQuick.Controls
import qs.Commons

// Single-line input on a tinted pill; the border shows only while focused.
TextField {
  id: root

  property bool error: false

  implicitHeight: Math.round(34 * Style.uiScaleRatio)
  leftPadding: Math.round(12 * Style.uiScaleRatio)
  rightPadding: Math.round(12 * Style.uiScaleRatio)
  verticalAlignment: TextInput.AlignVCenter
  font.family: Settings.data.ui.fontDefault
  font.pointSize: Style.fontSizeM * Style.uiScaleRatio
  color: Color.mOnSurface
  placeholderTextColor: Qt.alpha(Color.mOnSurface, 0.42)
  selectionColor: Qt.alpha(Color.mPrimary, 0.4)
  selectedTextColor: Color.mOnSurface
  selectByMouse: true

  background: Rectangle {
    radius: Math.round(12 * Style.uiScaleRatio)
    color: Qt.alpha(Color.mOnSurface, 0.07)
    border.width: Style.borderS
    border.color: root.error ? Qt.alpha(Color.mError, 0.6) : (root.activeFocus ? Qt.alpha(Color.mOnSurface, 0.22) : "transparent")
  }
}
