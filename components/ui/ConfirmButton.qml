import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
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
  // false while the action is being prepared (OK disabled, question can say so).
  property bool ready: true
  // True while the bubble is open: parents that show the button on hover keep it
  // visible, or hiding it would close the bubble under the pointer.
  readonly property bool asking: bubble.visible
  signal opened
  signal closed

  function close() {
    bubble.close();
  }

  danger: true
  onClicked: bubble.open()

  Popup {
    id: bubble
    // Opens below the button, right-aligned to it; flips above when the window
    // has no room below (placed on each open, since rows scroll).
    readonly property real gap: Math.round(6 * Style.uiScaleRatio)
    x: root.width - width
    y: root.height + gap
    onAboutToShow: {
      const below = root.height + gap;
      const win = root.Window.window;
      const top = win ? root.mapToItem(null, 0, 0).y : 0;
      y = win && top + below + implicitHeight > win.height ? -implicitHeight - gap : below;
    }
    margins: Style.marginS
    padding: Math.round(10 * Style.uiScaleRatio)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: { cancelButton.forceActiveFocus(); root.opened(); }
    onClosed: root.closed()

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
          enabled: root.ready
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
