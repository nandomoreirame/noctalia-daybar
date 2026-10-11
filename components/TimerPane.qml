import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/pomodoro.js" as Pomodoro
import "../utils/duration.js" as Duration
import "../utils/clock.js" as Clock

// Timer view of the Focus tab: a duration entry (field + presets) while no timer
// is set, then the ring with play/pause, reset and "new timer".
Item {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string error: ""
  readonly property bool hasTimer: (mainInstance?.timerTotal ?? 0) > 0
  readonly property bool running: mainInstance?.timerRunning ?? false
  readonly property int remaining: mainInstance?.timerRemaining ?? 0
  readonly property var presets: [1, 5, 10, 15, 30]

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function startFromField() {
    const d = Duration.parseDuration(entry.text);
    if (!d.ok) {
      error = tr("capture.error." + d.error);
      return;
    }
    error = "";
    entry.text = "";
    mainInstance.timerStartNew(d.seconds, d.label);
  }

  onVisibleChanged: if (visible && !hasTimer) entry.forceActiveFocus()
  // onVisibleChanged does not fire when the pane is created already visible.
  Component.onCompleted: if (visible && !hasTimer) entry.forceActiveFocus()

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width, Math.round(360 * Style.uiScaleRatio))
    spacing: Math.round(10 * Style.uiScaleRatio)
    visible: !root.hasTimer

    Field {
      id: entry
      Layout.fillWidth: true
      placeholderText: root.tr("timer.placeholder")
      maximumLength: 120
      error: root.error !== ""
      Accessible.name: root.tr("timer.placeholder")
      onTextChanged: root.error = ""
      Keys.onReturnPressed: root.startFromField()
      Keys.onEnterPressed: root.startFromField()
    }

    NText {
      Layout.fillWidth: true
      visible: root.error !== ""
      wrapMode: Text.WordWrap
      text: root.error
      pointSize: Style.fontSizeS
      color: Color.mError
      Accessible.role: Accessible.AlertMessage
      Accessible.name: text
    }

    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Math.round(4 * Style.uiScaleRatio)

      Repeater {
        model: root.presets

        Chip {
          required property int modelData
          text: root.tr("timer.preset").replace("{n}", modelData)
          onClicked: root.mainInstance.timerStartNew(modelData * 60, "")
        }
      }
    }

    PillButton {
      Layout.alignment: Qt.AlignHCenter
      primary: true
      implicitHeight: Math.round(34 * Style.uiScaleRatio)
      icon: "player-play"
      text: root.tr("focus.start")
      onClicked: root.startFromField()
    }

    NText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.tr("timer.entry-help")
      pointSize: Style.fontSizeXS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Math.round(8 * Style.uiScaleRatio)
    visible: root.hasTimer

    Item {
      Layout.fillHeight: true
    }

    ProgressRing {
      id: ring
      Layout.alignment: Qt.AlignHCenter
      progress: Clock.progress(root.remaining, root.mainInstance?.timerTotal ?? 0)
      arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
      accessibleName: root.tr("focus.mode.timer") + " " + Pomodoro.formatClock(root.remaining)

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        NText {
          Layout.alignment: Qt.AlignHCenter
          text: Pomodoro.formatClock(root.remaining)
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeXXXL * 1.6
          font.weight: Style.fontWeightBold
          color: root.running ? Color.mPrimary : Color.mOnSurface
        }

        NText {
          Layout.alignment: Qt.AlignHCenter
          Layout.maximumWidth: ring.width * 0.7
          visible: text !== ""
          elide: Text.ElideRight
          text: root.mainInstance?.timerLabel ?? ""
          pointSize: Style.fontSizeS
          color: Qt.alpha(Color.mOnSurface, 0.56)
        }
      }
    }

    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: Math.round(4 * Style.uiScaleRatio)
      spacing: Math.round(8 * Style.uiScaleRatio)

      PillButton {
        icon: "refresh"
        tooltipText: root.tr("focus.reset")
        onClicked: root.mainInstance.timerReset()
      }

      PillButton {
        primary: true
        implicitHeight: Math.round(34 * Style.uiScaleRatio)
        icon: root.running ? "player-pause" : "player-play"
        text: root.running ? root.tr("focus.pause") : root.tr("focus.start")
        onClicked: root.running ? root.mainInstance.timerPause() : root.mainInstance.timerStart()
      }

      PillButton {
        icon: "plus"
        tooltipText: root.tr("timer.new")
        onClicked: {
          root.mainInstance.timerClear();
          entry.forceActiveFocus();
        }
      }
    }

    Item {
      Layout.fillHeight: true
    }
  }
}
