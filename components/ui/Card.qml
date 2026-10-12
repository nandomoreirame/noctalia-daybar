import QtQuick 6.11
import qs.Commons

// Tinted surface for a tab's content: a faint ink wash with a hairline border.
Rectangle {
  radius: Style.radiusL
  color: Qt.alpha(Color.mOnSurface, 0.06)
  border.color: Qt.alpha(Color.mOnSurface, 0.06)
  border.width: Style.borderS
}
