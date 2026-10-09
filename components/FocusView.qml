import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "../utils/pomodoro.js" as Pomodoro
import "../utils/dates.js" as Dates

// Pomodoro controls with an optional link to one of today's tasks, today's
// progress against the daily goal and quick duration settings (gear button).
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property bool showSettings: false
  readonly property var modes: [["work", Pomodoro.WORK], ["short", Pomodoro.SHORT], ["long", Pomodoro.LONG]]
  readonly property var taskOptions: {
    const none = [{ key: "", name: tr("focus.no-task") }];
    if (!mainInstance)
      return none;
    const today = Dates.isoDate(new Date());
    return none.concat(mainInstance.data.tasks
      .filter(t => !t.done && (t.date || today) <= today)
      .map(t => ({ key: t.id, name: t.title })));
  }
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

  function progressText() {
    const base = dailyGoal > 0 ? tr("focus.today-goal").replace("{total}", dailyGoal) : tr("focus.today-count");
    return base.replace("{n}", sessionsToday);
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM
    visible: !root.showSettings

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginL

      NText {
        text: Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)
        family: Settings.data.ui.fontFixed
        pointSize: Style.fontSizeXXL * 1.6
        font.weight: Style.fontWeightBold
        color: root.mainInstance?.pomodoroRunning ? Color.mPrimary : Color.mOnSurface
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        RowLayout {
          spacing: Style.marginS

          Repeater {
            model: root.modes

            NButton {
              required property var modelData
              text: root.tr("focus.mode." + modelData[0])
              outlined: root.mainInstance?.pomodoroMode !== modelData[1]
              onClicked: root.mainInstance.pomodoroSetMode(modelData[1])
            }
          }
        }

        RowLayout {
          spacing: Style.marginM

          NComboBox {
            model: root.taskOptions
            currentKey: root.mainInstance?.linkedTaskId ?? ""
            placeholder: root.tr("focus.no-task")
            onSelected: key => root.mainInstance.linkedTaskId = key
          }

          NText {
            text: root.tr("focus.cycle").replace("{n}", (root.mainInstance?.pomodoroCompleted ?? 0) + 1).replace("{total}", root.mainInstance?.pomodoroConfig.sessionsBeforeLong ?? 4)
            color: Color.mOnSurfaceVariant
          }
        }

        RowLayout {
          spacing: Style.marginS

          NButton {
            text: root.mainInstance?.pomodoroRunning ? root.tr("focus.pause") : root.tr("focus.start")
            icon: root.mainInstance?.pomodoroRunning ? "player-pause" : "player-play"
            onClicked: root.mainInstance.pomodoroRunning ? root.mainInstance.pomodoroPause() : root.mainInstance.pomodoroStart()
          }

          NIconButton {
            icon: "refresh"
            tooltipText: root.tr("focus.reset")
            onClicked: root.mainInstance.pomodoroReset()
          }

          NIconButton {
            icon: "player-skip-forward"
            tooltipText: root.tr("focus.skip")
            onClicked: root.mainInstance.pomodoroSkip()
          }

          NIconButton {
            icon: "settings"
            tooltipText: root.tr("focus.settings")
            onClicked: root.showSettings = true
          }
        }
      }
    }

    // Today's progress: one dot per session of the daily goal.
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: root.progressText()
        color: root.dailyGoal > 0 && root.sessionsToday >= root.dailyGoal ? Color.mPrimary : Color.mOnSurfaceVariant
      }

      Repeater {
        model: root.dailyGoal

        Rectangle {
          required property int index
          width: 8 * Style.uiScaleRatio
          height: width
          radius: width / 2
          color: index < root.sessionsToday ? Color.mPrimary : "transparent"
          border.color: Color.mPrimary
          border.width: Style.borderS
        }
      }

      Item {
        Layout.fillWidth: true
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginS
    visible: root.showSettings

    RowLayout {
      Layout.fillWidth: true

      NText {
        Layout.fillWidth: true
        text: root.tr("focus.settings")
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NIconButton {
        icon: "x"
        tooltipText: root.tr("focus.settings-close")
        onClicked: root.showSettings = false
      }
    }

    NScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        width: parent.width
        spacing: Style.marginS

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
          color: Color.mOnSurfaceVariant
        }
      }
    }
  }
}
