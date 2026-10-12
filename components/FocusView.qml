import QtQuick 6.11
import QtQuick.Controls 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/pomodoro.js" as Pomodoro
import "../utils/dates.js" as Dates
import "../utils/clock.js" as Clock

// Focus: mode chips plus a Timer chip that switches to the countdown timer view.
// Pomodoro view: the clock inside a progress ring, an optional link to one of today's tasks,
// today's progress against the daily goal and quick settings (gear button).
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property bool showSettings: false
  // The task picker opens and closes with the + button; closing keeps the linked task,
  // which then shows as text under the controls.
  property bool showTaskPicker: false
  readonly property var modes: [["work", Pomodoro.WORK], ["short", Pomodoro.SHORT], ["long", Pomodoro.LONG], ["timer", Clock.TIMER_CHIP]]
  readonly property bool timerView: mainInstance?.focusPanel === "timer"
  readonly property var taskOptions: {
    const none = [{ key: "", name: tr("focus.no-task") }];
    if (!mainInstance)
      return none;
    const today = Dates.isoDate(new Date());
    return none.concat(mainInstance.data.tasks
      .filter(t => !t.done && (t.date || today) <= today)
      .map(t => ({ key: t.id, name: t.title })));
  }
  readonly property bool running: mainInstance?.pomodoroRunning ?? false
  readonly property int sessionsToday: mainInstance?.todaySessions ?? 0
  readonly property int dailyGoal: mainInstance?.pomodoroConfig.dailyGoal ?? 0
  // [label key, setting key, min, max, suffix]
  readonly property var quickSettings: [
    ["settings.work-duration", "workDuration", 1, 180, " min"],
    ["settings.short-break", "shortBreakDuration", 1, 60, " min"],
    ["settings.long-break", "longBreakDuration", 1, 120, " min"],
    ["settings.sessions", "sessionsBeforeLongBreak", 1, 12, ""],
    ["settings.daily-goal", "dailyPomodoroGoal", 0, 24, ""]
  ]

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  // Coming back from the Timer view to the current mode keeps the pomodoro running.
  function selectChip(chip) {
    mainInstance.selectFocusChip(chip);
  }

  function progressText() {
    const base = dailyGoal > 0 ? tr("focus.today-goal").replace("{total}", dailyGoal) : tr("focus.today-count");
    return base.replace("{n}", sessionsToday);
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)
    visible: !root.showSettings

    // Mode chips, centered.
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Math.round(4 * Style.uiScaleRatio)

      Repeater {
        model: root.modes

        Chip {
          required property var modelData
          text: root.tr("focus.mode." + modelData[0])
          selected: root.timerView ? modelData[1] === Clock.TIMER_CHIP : root.mainInstance?.pomodoroMode === modelData[1]
          onClicked: root.selectChip(modelData[1])
        }
      }
    }

    // Content area: the pomodoro pane or the timer view.
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        id: pomodoroPane
        anchors.fill: parent
        spacing: Math.round(8 * Style.uiScaleRatio)
        visible: !root.timerView

        // Everything below the header is one centered stack: ring (clock), controls
        // and the linked task.
        Item {
          Layout.fillHeight: true
        }

        ProgressRing {
          id: pomodoroRing
          Layout.alignment: Qt.AlignHCenter
          // Takes the height left in the panel (80 to 240 px), always round.
          Layout.fillHeight: true
          Layout.minimumHeight: Math.round(80 * Style.uiScaleRatio)
          Layout.preferredHeight: Math.round(240 * Style.uiScaleRatio)
          Layout.maximumHeight: Math.round(240 * Style.uiScaleRatio)
          Layout.preferredWidth: height
          progress: Clock.progress(root.mainInstance?.pomodoroRemaining ?? 0, root.mainInstance ? Pomodoro.durationFor(root.mainInstance.pomodoroMode, root.mainInstance.pomodoroConfig) : 0)
          arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
          accessibleName: root.tr("focus.mode." + root.modes[root.mainInstance?.pomodoroMode ?? 0][0]) + " " + Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)

          ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            NText {
              Layout.alignment: Qt.AlignHCenter
              // Narrower than the ring, so the numbers keep a margin from the stroke.
              Layout.preferredWidth: pomodoroRing.width * 0.62
              horizontalAlignment: Text.AlignHCenter
              fontSizeMode: Text.HorizontalFit
              minimumPointSize: Style.fontSizeM
              elide: Text.ElideNone
              text: Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)
              family: Settings.data.ui.fontFixed
              pointSize: Style.fontSizeXXXL * 2.6
              font.weight: Style.fontWeightBold
              color: root.running ? Color.mPrimary : Color.mOnSurface
            }
          }
        }

        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: Math.round(4 * Style.uiScaleRatio)
          spacing: Math.round(8 * Style.uiScaleRatio)

          PillButton {
            icon: "plus"
            primary: root.showTaskPicker
            tooltipText: root.tr("focus.link-task")
            onClicked: root.showTaskPicker = !root.showTaskPicker
          }

          PillButton {
            icon: "refresh"
            tooltipText: root.tr("focus.reset")
            onClicked: root.mainInstance.pomodoroReset()
          }

          PillButton {
            primary: true
            implicitHeight: Math.round(34 * Style.uiScaleRatio)
            icon: root.running ? "player-pause" : "player-play"
            text: root.running ? root.tr("focus.pause") : root.tr("focus.start")
            onClicked: root.running ? root.mainInstance.pomodoroPause() : root.mainInstance.pomodoroStart()
          }

          PillButton {
            icon: "player-skip-forward"
            tooltipText: root.tr("focus.skip")
            onClicked: root.mainInstance.pomodoroSkip()
          }
        }

        NComboBox {
          // The empty built-in label would take any width beyond minimumWidth and push
          // the box off center, so size the box through minimumWidth only.
          Layout.alignment: Qt.AlignHCenter
          visible: root.showTaskPicker
          minimumWidth: 320
          model: root.taskOptions
          currentKey: root.mainInstance?.linkedTaskId ?? ""
          placeholder: root.tr("focus.no-task")
          onSelected: key => root.mainInstance.linkedTaskId = key
        }

        NText {
          Layout.alignment: Qt.AlignHCenter
          Layout.maximumWidth: Math.round(320 * Style.uiScaleRatio)
          visible: !root.showTaskPicker && text !== ""
          elide: Text.ElideRight
          text: root.mainInstance?.linkedTaskTitle ?? ""
          pointSize: Style.fontSizeS
          color: Qt.alpha(Color.mOnSurface, 0.56)
        }

        Item {
          Layout.fillHeight: true
        }
      }

      TimerPane {
        anchors.fill: parent
        visible: root.timerView
        pluginApi: root.pluginApi
        mainInstance: root.mainInstance
      }
    }

    // Footer: detached clock and settings on the left, today's progress on the right.
    RowLayout {
      Layout.fillWidth: true
      spacing: Math.round(4 * Style.uiScaleRatio)

      // Detached clock: floating window and corner overlay (both views).
      PillButton {
        icon: "picture-in-picture"
        primary: root.mainInstance?.clockWindowOpen ?? false
        tooltipText: root.tr(primary ? "focus.clock-window-close" : "focus.clock-window-open")
        onClicked: root.mainInstance?.setClockWindow(!root.mainInstance.clockWindowOpen)
      }

      PillButton {
        icon: root.mainInstance?.clockOverlayOpen ? "pinned" : "pin"
        primary: root.mainInstance?.clockOverlayOpen ?? false
        tooltipText: root.tr(primary ? "focus.clock-overlay-close" : "focus.clock-overlay-open")
        onClicked: root.mainInstance?.setClockOverlay(!root.mainInstance.clockOverlayOpen)
      }

      PillButton {
        visible: !root.timerView
        icon: "settings"
        tooltipText: root.tr("focus.settings")
        onClicked: root.showSettings = true
      }

      Item {
        Layout.fillWidth: true
      }

      // Today's sessions against the daily goal.
      NText {
        visible: !root.timerView
        Layout.rightMargin: Math.round(4 * Style.uiScaleRatio)
        text: root.progressText()
        pointSize: Style.fontSizeS
        color: root.dailyGoal > 0 && root.sessionsToday >= root.dailyGoal ? Color.mPrimary : Qt.alpha(Color.mOnSurface, 0.56)
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)
    visible: root.showSettings

    RowLayout {
      Layout.fillWidth: true

      NText {
        Layout.fillWidth: true
        text: root.tr("focus.settings")
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
      }

      PillButton {
        icon: "x"
        tooltipText: root.tr("focus.settings-close")
        onClicked: root.showSettings = false
      }
    }

    NScrollView {
      id: settingsScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      contentWidth: availableWidth
      horizontalPolicy: ScrollBar.AlwaysOff

      ColumnLayout {
        width: settingsScroll.availableWidth
        spacing: Math.round(6 * Style.uiScaleRatio)

        Repeater {
          model: root.quickSettings

          NSpinBox {
            required property var modelData
            label: root.tr(modelData[0])
            from: modelData[2]
            to: modelData[3]
            suffix: modelData[4]
            value: root.mainInstance?.setting(modelData[1]) ?? modelData[2]
            onValueChanged: {
              if (root.mainInstance && value !== root.mainInstance.setting(modelData[1]))
                root.mainInstance.setSetting(modelData[1], value);
            }
          }
        }

        NText {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: root.tr("focus.settings-help")
          pointSize: Style.fontSizeXS
          color: Qt.alpha(Color.mOnSurface, 0.56)
        }
      }
    }
  }
}
