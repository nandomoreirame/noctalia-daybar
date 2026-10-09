import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "utils/capture/registry.js" as Registry
import "utils/format.js" as Format

// Centered quick-capture overlay. Enter saves and closes, Shift+Enter saves and
// stays, Tab cycles the type, Esc or a click outside closes without saving.
PanelWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string forcedType: ""
  property var result: ({ ok: false, type: "task", error: "empty" })
  property bool busy: false
  property string feedback: ""
  property bool feedbackIsError: false

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-daybar-capture"
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function openOn(targetScreen) {
    if (visible) {
      field.forceActiveFocus();
      return;
    }
    screen = targetScreen;
    forcedType = "";
    busy = false;
    field.text = "";
    visible = true;
    refresh();
    field.forceActiveFocus();
  }

  // Clipboard URL arrives asynchronously; only fill an untouched field.
  function prefill(url) {
    if (!visible || field.text !== "")
      return;
    field.text = url;
    field.selectAll();
    refresh();
  }

  function close() {
    visible = false;
    field.text = "";
  }

  function refresh() {
    result = Registry.resolve(field.text, forcedType || null, new Date());
    feedback = "";
  }

  function cycleType() {
    if (result.type === "calculation")
      return;
    forcedType = Registry.nextType(result.type);
    refresh();
  }

  function previewText(r) {
    if (!r.ok)
      return field.text.trim() === "" ? tr("capture.hint") : tr("capture.error." + r.error);
    const p = r.payload;
    if (r.type === "calculation")
      return "= " + p.display;
    if (r.type === "note")
      return p.text;
    if (r.type === "link")
      return p.url;
    const w = Format.describeWhen(p.date, p.time || p.start, r.type === "task" ? null : p.endTime, new Date());
    const day = w.day === "today" || w.day === "tomorrow" ? tr("when." + w.day) : w.day;
    return [p.title, [day, w.time].filter(s => s).join(" ")].filter(s => s).join("  ·  ");
  }

  function submit(keepOpen) {
    if (busy)
      return;
    refresh();
    const r = result;
    if (!r.ok) {
      feedback = tr("capture.error." + r.error);
      feedbackIsError = true;
      return;
    }
    if (r.action === "copy") {
      mainInstance.copyText(r.payload.display);
      feedback = tr("capture.copied");
      feedbackIsError = false;
      return;
    }
    busy = true;
    mainInstance.executeCapture(r, function (ok, error) {
      busy = false;
      if (!ok) {
        feedback = tr("capture.error." + error);
        feedbackIsError = true;
        return;
      }
      ToastService.showNotice(tr("capture.saved." + r.type), previewText(r), "check");
      if (keepOpen) {
        field.text = "";
        forcedType = "";
        refresh();
        field.forceActiveFocus();
      } else {
        root.close();
      }
    });
  }

  // Dimmed backdrop; clicking outside the card closes.
  MouseArea {
    anchors.fill: parent
    onClicked: root.close()

    Rectangle {
      anchors.fill: parent
      color: Qt.alpha(Color.mShadow, 0.35)
    }
  }

  Rectangle {
    id: card
    width: Math.min(640 * Style.uiScaleRatio, parent.width - Style.marginL * 2)
    height: column.implicitHeight + Style.marginL * 2
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height * 0.28
    radius: Style.radiusL
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Style.borderS

    // Swallow clicks so they do not reach the backdrop.
    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        spacing: Style.marginS

        Repeater {
          model: Registry.CYCLE

          Rectangle {
            required property string modelData
            readonly property bool active: root.result.type === modelData
            implicitWidth: chipLabel.implicitWidth + Style.marginM * 2
            implicitHeight: chipLabel.implicitHeight + Style.marginXS * 2
            radius: Style.radiusM
            color: active ? Color.mPrimary : "transparent"

            NText {
              id: chipLabel
              anchors.centerIn: parent
              text: root.tr("capture.type." + modelData)
              pointSize: Style.fontSizeS
              color: parent.active ? Color.mOnPrimary : Color.mOnSurfaceVariant
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.forcedType = modelData;
                root.refresh();
                field.forceActiveFocus();
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
        }

        NText {
          visible: root.result.type === "calculation"
          text: root.tr("capture.type.calculation")
          pointSize: Style.fontSizeS
          color: Color.mPrimary
        }
      }

      TextField {
        id: field
        Layout.fillWidth: true
        font.pointSize: Style.fontSizeL * Style.uiScaleRatio
        color: Color.mOnSurface
        placeholderText: root.tr("capture.placeholder")
        placeholderTextColor: Color.mOnSurfaceVariant
        selectByMouse: true
        maximumLength: 500
        enabled: !root.busy
        background: Rectangle {
          radius: Style.radiusM
          color: Color.mSurfaceVariant
          border.color: field.activeFocus ? Color.mPrimary : Color.mOutline
          border.width: Style.borderS
        }
        leftPadding: Style.marginM
        rightPadding: Style.marginM
        topPadding: Style.marginS
        bottomPadding: Style.marginS

        onTextChanged: root.refresh()

        Keys.onTabPressed: event => {
          root.cycleType();
          event.accepted = true;
        }
        Keys.onBacktabPressed: event => {
          event.accepted = true;
        }
        Keys.onEscapePressed: event => {
          root.close();
          event.accepted = true;
        }
        Keys.onReturnPressed: event => {
          root.submit(event.modifiers & Qt.ShiftModifier);
          event.accepted = true;
        }
        Keys.onEnterPressed: event => {
          root.submit(event.modifiers & Qt.ShiftModifier);
          event.accepted = true;
        }
      }

      NText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.feedback !== "" ? root.feedback : root.previewText(root.result)
        pointSize: Style.fontSizeS
        color: root.feedback !== "" && root.feedbackIsError ? Color.mError : Color.mOnSurfaceVariant
      }

      NText {
        Layout.fillWidth: true
        text: root.tr("capture.keys")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        opacity: 0.7
      }
    }
  }
}
