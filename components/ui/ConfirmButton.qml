import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Icon button that asks before acting: a bubble anchored to it with a question,
// "OK" and "Cancel". Focus starts on Cancel; Esc or a click outside cancels.
PillButton {
  id: root

  property string question: ""
  property string okText: "OK"
  property string cancelText: "Cancel"
  signal confirmed

  danger: true
  onClicked: bubble.open()

  Popup {
    id: bubble
    // Opens below the button, right-aligned to it; flips above when there is no room.
    readonly property real gap: Math.round(6 * Style.uiScaleRatio)
    x: root.width - width
    y: root.height + gap
    margins: Style.marginS
    padding: Math.round(10 * Style.uiScaleRatio)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: cancelButton.forceActiveFocus()

    background: Rectangle {
      radius: Math.round(12 * Style.uiScaleRatio)
      color: Color.mSurface
      border.color: Qt.alpha(Color.mOnSurface, 0.12)
      border.width: Style.borderS
    }

    contentItem: ColumnLayout {
      spacing: Math.round(8 * Style.uiScaleRatio)

      NText {
        text: root.question
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
      }

      RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Math.round(6 * Style.uiScaleRatio)

        PillButton {
          id: cancelButton
          text: root.cancelText
          onClicked: bubble.close()
        }

        PillButton {
          primary: true
          text: root.okText
          onClicked: {
            bubble.close();
            root.confirmed();
          }
        }
      }
    }
  }
}
