import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Location
import "../utils/today.js" as Today
import "../utils/capture/task.js" as TaskCapture

// Today checklist: calendar events + today's and overdue tasks, plus a quick add field.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property date now: new Date()
  readonly property var items: mainInstance ? Today.buildToday(mainInstance.visibleEvents, mainInstance.data, now) : []

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS

    NText {
      text: root.tr("today.title")
      pointSize: Style.fontSizeM
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }

    NText {
      visible: root.items.length === 0
      text: root.tr("today.empty")
      color: Color.mOnSurfaceVariant
    }

    NScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.items.length > 0

      ColumnLayout {
        width: parent.width
        spacing: Style.marginXS

        Repeater {
          model: root.items

          RowLayout {
            id: row
            required property var modelData
            readonly property bool hovered: rowHover.hovered
            HoverHandler { id: rowHover }
            Layout.fillWidth: true
            spacing: Style.marginS

            NCheckbox {
              checked: modelData.done
              onToggled: {
                if (modelData.kind === "event")
                  root.mainInstance.toggleEvent(modelData.uid, Qt.formatDate(root.now, "yyyy-MM-dd"));
                else
                  root.mainInstance.toggleTask(modelData.id);
              }
            }

            NIcon {
              icon: modelData.kind === "event" ? "calendar" : "checkbox"
              color: Color.mOnSurfaceVariant
            }

            NText {
              visible: modelData.time !== null
              text: modelData.time || ""
              family: Settings.data.ui.fontFixed
              color: Color.mPrimary
            }

            NText {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: modelData.title
              color: modelData.done ? Color.mOnSurfaceVariant : Color.mOnSurface
              font.strikeout: modelData.done
            }

            NText {
              visible: modelData.overdue
              text: root.tr("today.overdue")
              pointSize: Style.fontSizeXS
              color: Color.mError
            }

            NText {
              visible: modelData.pomodoros > 0
              text: "● " + modelData.pomodoros
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Item {
              implicitWidth: Math.round(24 * Style.uiScaleRatio)
              implicitHeight: implicitWidth
              visible: row.modelData.kind === "task"

              NIconButton {
                anchors.fill: parent
                icon: "trash"
                baseSize: Style.baseWidgetSize * 0.7
                tooltipText: root.tr("today.delete")
                onClicked: root.mainInstance.deleteTask(row.modelData.id)
              }
            }

            Item {
              implicitWidth: Math.round(24 * Style.uiScaleRatio)
              implicitHeight: implicitWidth
              visible: row.modelData.kind === "event"

              EventDeleteButton {
                id: eventTrash
                anchors.fill: parent
                visible: (row.hovered || activeFocus || asking) && (root.mainInstance?.canDeleteEvent(row.modelData.calendar) ?? false)
                pluginApi: root.pluginApi
                mainInstance: root.mainInstance
                uid: row.modelData.uid
                calendar: row.modelData.calendar
              }
            }
          }
        }
      }
    }

    NTextInput {
      id: addField
      Layout.fillWidth: true
      placeholderText: root.tr("today.add-placeholder")
      onAccepted: {
        const r = TaskCapture.build(addField.text, new Date());
        if (!r.ok)
          return;
        root.mainInstance.addTask(r.payload);
        addField.text = "";
      }
    }
  }
}
