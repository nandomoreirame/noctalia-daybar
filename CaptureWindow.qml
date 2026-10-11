import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "components/ui"
import "utils/capture/registry.js" as Registry
import "utils/capture/timer.js" as TimerCapture
import "utils/capture/pomodoro.js" as PomodoroCapture
import "utils/clock.js" as Clock
import "utils/format.js" as Format
import "utils/pomodoro.js" as Pomodoro
import "utils/tabs.js" as Tabs

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
  // Bumped on every open and close, so a slow khal write can tell whether the
  // overlay it was started from is still the one on screen.
  property int session: 0
  readonly property var typeIcons: ({ task: "checkbox", event: "calendar-event", reminder: "bell", note: "note", link: "link", calculation: "calculator", timer: Clock.TIMER_ICON, pomodoro: Tabs.ICONS.focus })
  // Types outside the Tab cycle (calculation, pomodoro) are shown as a header label.
  readonly property bool offCycle: Registry.CYCLE.indexOf(result.type) < 0
  readonly property bool isCommand: isCommandType(result.type)

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
    session += 1;
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
    session += 1;
    field.text = "";
  }

  function refresh() {
    result = Registry.resolve(field.text, forcedType || null, new Date());
    feedback = "";
  }

  // step: 1 for Tab, -1 for Shift+Tab.
  function cycleType(step) {
    if (offCycle)
      return;
    forcedType = step < 0 ? Registry.prevType(result.type) : Registry.nextType(result.type);
    refresh();
  }

  function previewText(r) {
    if (!r.ok)
      return field.text.trim() === "" ? tr("capture.hint") : tr("capture.error." + r.error);
    const p = r.payload;
    if (r.type === "timer") {
      const timer = { set: mainInstance.timerTotal > 0, running: mainInstance.timerRunning, ringing: mainInstance.timerSoundPlaying };
      const key = TimerCapture.previewKey(r.action, timer);
      if (r.action !== "startTimer")
        return tr(key);
      const head = timerHead(p);
      return key ? head + "  ·  " + tr(key).replace("{clock}", Pomodoro.formatClock(mainInstance.timerRemaining)) : head;
    }
    if (r.type === "pomodoro")
      return tr(PomodoroCapture.previewKey(p.command, { running: mainInstance.pomodoroRunning, mode: mainInstance.pomodoroMode }));
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

  function timerHead(p) {
    return [Pomodoro.formatClock(p.seconds), p.label].filter(s => s).join("  ·  ");
  }

  // Commands have no "saved" wording; their toast is titled with the type.
  function savedTitle(r) {
    return isCommandType(r.type) ? tr("capture.type." + r.type) : tr("capture.saved." + r.type);
  }

  function isCommandType(type) {
    return type === "timer" || type === "pomodoro";
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
    const startedIn = session;
    const typedText = field.text;
    // Commands describe the state BEFORE they run, so capture the line now. A new
    // timer's toast drops the "replaces" note, which is stale once it ran.
    const shown = r.action === "startTimer" ? timerHead(r.payload) : previewText(r);
    mainInstance.executeCapture(r, function (ok, error) {
      if (startedIn !== root.session) {
        // The overlay was closed or reopened meanwhile: report through a toast
        // and leave the current field alone.
        if (ok)
          ToastService.showNotice(savedTitle(r), shown, "check");
        else
          ToastService.showWarning(tr("capture.failed-title"), tr("capture.error." + error) + "\n" + typedText);
        return;
      }
      busy = false;
      if (!ok) {
        feedback = tr("capture.error." + error);
        feedbackIsError = true;
        return;
      }
      ToastService.showNotice(savedTitle(r), shown, "check");
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
    border.color: Qt.alpha(Color.mOnSurface, 0.08)
    border.width: Style.borderS

    // Swallow clicks so they do not reach the backdrop.
    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Math.round(14 * Style.uiScaleRatio)
      spacing: Math.round(10 * Style.uiScaleRatio)

      RowLayout {
        spacing: Math.round(4 * Style.uiScaleRatio)

        IconTabs {
          controlled: true
          model: Registry.CYCLE.map(k => ({ key: k, icon: root.typeIcons[k], label: root.tr("capture.type." + k) }))
          currentIndex: Registry.CYCLE.indexOf(root.result.type)
          onActivated: index => {
            root.forcedType = Registry.CYCLE[index];
            root.refresh();
            field.forceActiveFocus();
          }
        }

        Item {
          Layout.fillWidth: true
        }

        RowLayout {
          visible: root.offCycle
          spacing: Math.round(5 * Style.uiScaleRatio)

          NIcon {
            icon: root.typeIcons[root.result.type] ?? ""
            pointSize: Style.fontSizeM
            color: Color.mPrimary
          }

          NText {
            text: root.tr("capture.type." + root.result.type)
            pointSize: Style.fontSizeS
            font.weight: Style.fontWeightSemiBold
            color: Color.mPrimary
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(8 * Style.uiScaleRatio)

        Field {
          id: field
          Layout.fillWidth: true
          font.pointSize: Style.fontSizeL * Style.uiScaleRatio
          // Only shown while empty, when the type is the Tab choice or the task default.
          placeholderText: root.tr("capture.placeholders." + (root.offCycle ? "task" : root.result.type))
          maximumLength: 500
          enabled: !root.busy
          error: root.feedback !== "" && root.feedbackIsError

          onTextChanged: root.refresh()

          Keys.onTabPressed: event => {
            root.cycleType(1);
            event.accepted = true;
          }
          Keys.onBacktabPressed: event => {
            root.cycleType(-1);
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

        PillButton {
          primary: true
          implicitHeight: field.implicitHeight
          text: root.result.type === "calculation" ? root.tr("capture.copy") : (root.isCommand ? root.tr("capture.run") : root.tr("capture.save"))
          enabled: !root.busy
          onClicked: root.submit(false)
        }
      }

      NText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        Layout.leftMargin: Math.round(4 * Style.uiScaleRatio)
        text: root.feedback !== "" ? root.feedback : root.previewText(root.result)
        pointSize: Style.fontSizeS
        color: root.feedback !== "" && root.feedbackIsError ? Color.mError : Qt.alpha(Color.mOnSurface, 0.6)
      }

      NText {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(4 * Style.uiScaleRatio)
        text: root.tr("capture.keys")
        pointSize: Style.fontSizeXS
        color: Qt.alpha(Color.mOnSurface, 0.42)
      }
    }
  }
}
