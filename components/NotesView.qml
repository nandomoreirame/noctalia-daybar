import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
  readonly property var all: mainInstance ? Notes.sorted(mainInstance.data.notes) : []
  readonly property var items: Notes.search(all, query)

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function when(iso) {
    const r = Format.relativeTime(iso, now);
    return r.unit === "date" ? r.date : tr("time." + r.unit).replace("{n}", r.n);
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

      PillButton {
        primary: true
        implicitHeight: Math.round(34 * Style.uiScaleRatio)
        icon: "plus"
        text: root.tr("notes.new")
        onClicked: root.mainInstance.newNote()
      }
    }

    NText {
      visible: root.items.length === 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Math.round(6 * Style.uiScaleRatio)
      text: root.all.length === 0 ? root.tr("notes.empty") : root.tr("notes.no-results")
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

            RowLayout {
              spacing: Math.round(2 * Style.uiScaleRatio)
              opacity: row.hovered || row.activeFocus ? 1 : 0
              enabled: opacity > 0

              PillButton {
                icon: "copy"
                tooltipText: root.tr("notes.copy")
                onClicked: root.mainInstance.copyText(row.modelData.text)
              }
              ConfirmButton {
                icon: "trash"
                tooltipText: root.tr("notes.delete")
                question: root.tr("notes.confirm-delete")
                okText: root.tr("confirm.ok")
                cancelText: root.tr("confirm.cancel")
                onConfirmed: root.mainInstance.deleteNote(row.modelData.id)
              }
            }

            TapHandler {
              onTapped: root.mainInstance.openNote(row.modelData.id)
            }
          }
        }
      }
    }
  }
}
