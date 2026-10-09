import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "../utils/pomodoro.js" as Pomodoro
import "../utils/dates.js" as Dates

// Pomodoro controls with an optional link to one of today's tasks.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
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

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
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
          text: root.tr("focus.cycle").replace("{n}", (root.mainInstance?.pomodoroCompleted ?? 0) + 1).replace("{total}", root.mainInstance?.setting("sessionsBeforeLongBreak") ?? 4)
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
      }
    }
  }
}
