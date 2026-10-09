import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Location
import "ui"
import "../utils/today.js" as Today
import "../utils/capture/task.js" as TaskCapture

// Today checklist: calendar events + today's and overdue tasks, plus a quick add field.
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property date now: new Date()
  // Freeze the list while a delete bubble is open so the Repeater does not
  // destroy the delegate under the Popup.
  property int asking: 0
  property var frozenItems: []
  readonly property var liveItems: mainInstance ? Today.buildToday(mainInstance.visibleEvents, mainInstance.data, now) : []
  readonly property var items: asking > 0 ? frozenItems : liveItems
  onLiveItemsChanged: if (asking === 0) frozenItems = liveItems
  onAskingChanged: if (asking === 0) frozenItems = liveItems
  readonly property int doneCount: items.filter(i => i.done).length
  // Id of the task whose title is being edited in place, or "".
  property string editingId: ""

  function startEdit(item) {
    if (item.kind === "task")
      editingId = item.id;
  }

  function finishEdit(id, text) {
    if (editingId !== id)
      return;
    editingId = "";
    mainInstance.renameTask(id, text);
  }

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
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Math.round(6 * Style.uiScaleRatio)
      Layout.rightMargin: Math.round(6 * Style.uiScaleRatio)

      NText {
        Layout.fillWidth: true
        text: root.tr("today.title")
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
      }

      NText {
        visible: root.items.length > 0
        text: root.tr("today.progress").replace("{n}", root.doneCount).replace("{total}", root.items.length)
        pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.56)
      }
    }

    NText {
      visible: root.items.length === 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Math.round(6 * Style.uiScaleRatio)
      text: root.tr("today.empty")
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }

    NScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.items.length > 0
      contentWidth: availableWidth
      horizontalPolicy: ScrollBar.AlwaysOff

      ColumnLayout {
        width: scroll.availableWidth
        spacing: Math.round(2 * Style.uiScaleRatio)

        Repeater {
          model: root.items

          ListRow {
            id: row
            required property var modelData

            CheckDot {
              checked: row.modelData.done
              label: row.modelData.title
              onToggled: {
                if (row.modelData.kind === "event")
                  root.mainInstance.toggleEvent(row.modelData.uid, Qt.formatDate(root.now, "yyyy-MM-dd"));
                else
                  root.mainInstance.toggleTask(row.modelData.id);
              }
            }

            NIcon {
              visible: row.modelData.kind === "event"
              icon: "calendar-event"
              pointSize: Style.fontSizeM
              color: Qt.alpha(Color.mOnSurface, 0.56)
            }

            NText {
              visible: row.modelData.time !== null
              text: row.modelData.time || ""
              family: Settings.data.ui.fontFixed
              pointSize: Style.fontSizeS
              color: Qt.alpha(Color.mOnSurface, 0.56)
            }

            // Title: double-click (or Enter when focused) edits a task in place.
            Item {
              id: titleSlot
              readonly property bool editing: root.editingId !== "" && root.editingId === row.modelData.id
              Layout.fillWidth: true
              implicitHeight: editing ? editField.implicitHeight : titleText.implicitHeight
              activeFocusOnTab: row.modelData.kind === "task" && !editing
              Accessible.role: Accessible.Button
              Accessible.name: row.modelData.title
              Accessible.description: row.modelData.kind === "task" ? root.tr("today.edit-hint") : ""
              Keys.onReturnPressed: root.startEdit(row.modelData)

              NText {
                id: titleText
                visible: !titleSlot.editing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: row.modelData.title
                pointSize: Style.fontSizeM
                color: row.modelData.done ? Qt.alpha(Color.mOnSurface, 0.42) : Color.mOnSurface
                font.strikeout: row.modelData.done
                font.underline: titleSlot.activeFocus
              }

              MouseArea {
                anchors.fill: parent
                enabled: !titleSlot.editing && row.modelData.kind === "task"
                cursorShape: Qt.IBeamCursor
                onDoubleClicked: root.startEdit(row.modelData)
              }

              Field {
                id: editField
                visible: titleSlot.editing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: Math.round(28 * Style.uiScaleRatio)
                Accessible.name: root.tr("today.rename")
                onVisibleChanged: {
                  if (visible) {
                    text = row.modelData.title;
                    selectAll();
                    forceActiveFocus();
                  }
                }
                onAccepted: root.finishEdit(row.modelData.id, text)
                Keys.onEscapePressed: root.editingId = ""
                onActiveFocusChanged: if (!activeFocus && visible) root.finishEdit(row.modelData.id, text)
              }
            }

            Rectangle {
              visible: row.modelData.overdue
              implicitHeight: Math.round(18 * Style.uiScaleRatio)
              implicitWidth: overdueLabel.implicitWidth + Math.round(12 * Style.uiScaleRatio)
              radius: height / 2
              color: Qt.alpha(Color.mError, 0.14)

              NText {
                id: overdueLabel
                anchors.centerIn: parent
                text: root.tr("today.overdue")
                pointSize: Style.fontSizeXS
                font.weight: Style.fontWeightMedium
                color: Color.mError
              }
            }

            NText {
              visible: row.modelData.pomodoros > 0
              text: "● " + row.modelData.pomodoros
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
            }

            // Fixed slots so rows keep one alignment whether or not the buttons show.
            Item {
              implicitWidth: Math.round(24 * Style.uiScaleRatio)
              implicitHeight: implicitWidth

              PillButton {
                anchors.fill: parent
                visible: row.modelData.kind === "task" && !row.modelData.done && (row.hovered || activeFocus)
                enabled: root.mainInstance?.canFocusTask ?? false
                icon: "player-play"
                tooltipText: root.tr("today.focus")
                onClicked: root.mainInstance.focusTask(row.modelData.id)
              }
            }

            Item {
              implicitWidth: Math.round(24 * Style.uiScaleRatio)
              implicitHeight: implicitWidth
              visible: row.modelData.kind === "task"

              PillButton {
                anchors.fill: parent
                visible: row.hovered || activeFocus
                icon: "trash"
                danger: true
                tooltipText: root.tr("today.delete")
                onClicked: root.mainInstance.deleteTask(row.modelData.id)
              }
            }

            Item {
              implicitWidth: Math.round(24 * Style.uiScaleRatio)
              implicitHeight: implicitWidth
              visible: row.modelData.kind === "event" && (root.mainInstance?.canDeleteEvent(row.modelData.calendar) ?? false)

              EventDeleteButton {
                id: eventTrash
                anchors.fill: parent
                opacity: row.hovered || row.focusInside || asking ? 1 : 0
                pluginApi: root.pluginApi
                mainInstance: root.mainInstance
                uid: row.modelData.uid
                calendar: row.modelData.calendar
                onOpened: root.asking++
                onClosed: root.asking = Math.max(0, root.asking - 1)
              }
            }
          }
        }
      }
    }

    Field {
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
