import QtQuick 6.11
import QtQuick.Controls 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/notes.js" as Notes
import "../utils/format.js" as Format

// Notes list: derived title, one-line snippet, relative edit time; search and
// "New note" on top. A click opens the note window.
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string query: ""
  property date now: new Date()
  property int asking: 0
  property var frozenItems: []
  readonly property var all: mainInstance ? Notes.sorted(mainInstance.data.notes) : []
  readonly property var liveItems: Notes.search(all, query)
  readonly property var items: asking > 0 ? frozenItems : liveItems
  onLiveItemsChanged: if (asking === 0) frozenItems = liveItems
  onAskingChanged: if (asking === 0) frozenItems = liveItems

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function when(iso) {
    const r = Format.relativeTime(iso, now);
    const k = Format.relativeKey(r);
    return k.key === "" ? k.date : tr(k.key).replace("{n}", k.n);
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.visible
    onTriggered: root.now = new Date()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)

    RowLayout {
      Layout.fillWidth: true
      spacing: Math.round(8 * Style.uiScaleRatio)

      Field {
        Layout.fillWidth: true
        placeholderText: root.tr("notes.search")
        onTextChanged: root.query = text
        Keys.onEscapePressed: text = ""
      }

      // The empty state offers its own "New note" button.
      PillButton {
        visible: root.all.length > 0
        primary: true
        implicitHeight: Math.round(34 * Style.uiScaleRatio)
        icon: "plus"
        text: root.tr("notes.new")
        onClicked: root.mainInstance.newNote()
      }
    }

    EmptyState {
      visible: root.items.length === 0
      icon: root.all.length === 0 ? "notes" : "search"
      title: root.all.length === 0 ? root.tr("notes.empty-title") : root.tr("notes.no-results")
      description: root.all.length === 0 ? root.tr("notes.empty") : ""
      actionText: root.all.length === 0 ? root.tr("notes.new") : ""
      actionIcon: "plus"
      onAction: root.mainInstance.newNote()
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
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Notes.titleOf(modelData.text) || root.tr("notes.untitled")
            Keys.onReturnPressed: root.mainInstance.openNote(modelData.id)

            NIcon {
              icon: "note"
              pointSize: Style.fontSizeM
              color: Qt.alpha(Color.mOnSurface, 0.56)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: Notes.titleOf(row.modelData.text) || root.tr("notes.untitled")
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightSemiBold
                color: Color.mOnSurface
              }

              NText {
                visible: text !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: Notes.snippetOf(row.modelData.text)
                pointSize: Style.fontSizeS
                color: Qt.alpha(Color.mOnSurface, 0.56)
              }
            }

            NText {
              text: root.when(row.modelData.updatedAt)
              pointSize: Style.fontSizeXS
              color: Qt.alpha(Color.mOnSurface, 0.42)
            }

            // Shown on hover, while keyboard focus is inside, or while the delete
            // bubble is open (it lives outside the row, so hover/focus leave the row).
            // Never disabled: disabled buttons can't take Tab focus or answer the bubble.
            RowLayout {
              id: actions
              spacing: Math.round(2 * Style.uiScaleRatio)
              opacity: row.hovered || row.focusInside || noteTrash.asking ? 1 : 0

              PillButton {
                icon: "copy"
                tooltipText: root.tr("notes.copy")
                onClicked: root.mainInstance.copyText(row.modelData.text)
              }
              ConfirmButton {
                id: noteTrash
                icon: "trash"
                tooltipText: root.tr("notes.delete")
                question: root.tr("notes.confirm-delete")
                okText: root.tr("confirm.ok")
                cancelText: root.tr("confirm.cancel")
                onConfirmed: root.mainInstance.deleteNote(row.modelData.id)
                onOpened: root.asking++
                onClosed: root.asking = Math.max(0, root.asking - 1)
              }
            }

            TapHandler {
              onTapped: root.mainInstance.openNote(row.modelData.id)
            }

            HoverHandler {
              cursorShape: Qt.PointingHandCursor
            }
          }
        }
      }
    }
  }
}
