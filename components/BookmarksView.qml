import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/bookmarks.js" as Bookmarks
import "../utils/url.js" as Url
import "../utils/dates.js" as Dates

// Bookmarks: browser-like rows (thumbnail, title, description, domain · date),
// search on top, add field at the bottom. Metadata is untrusted: PlainText only.
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string query: ""
  property string editingId: ""
  property string feedback: ""
  property int asking: 0
  property var frozenItems: []
  readonly property var all: mainInstance ? Bookmarks.sorted(mainInstance.data.bookmarks) : []
  readonly property var liveItems: Bookmarks.search(all, query)
  readonly property var items: asking > 0 ? frozenItems : liveItems
  onLiveItemsChanged: if (asking === 0) frozenItems = liveItems
  onAskingChanged: if (asking === 0) frozenItems = liveItems

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function finishRename(id, text) {
    if (editingId !== id)
      return;
    editingId = "";
    mainInstance.renameBookmark(id, text);
  }

  Timer {
    id: feedbackTimer
    interval: 2500
    onTriggered: root.feedback = ""
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)

    Field {
      Layout.fillWidth: true
      placeholderText: root.tr("bookmarks.search")
      onTextChanged: root.query = text
      Keys.onEscapePressed: text = ""
    }

    EmptyState {
      visible: root.items.length === 0
      icon: root.all.length === 0 ? "bookmark" : "search"
      title: root.all.length === 0 ? root.tr("bookmarks.empty-title") : root.tr("bookmarks.no-results")
      description: root.all.length === 0 ? root.tr("bookmarks.empty") : ""
      actionText: root.all.length === 0 ? root.tr("bookmarks.add") : ""
      actionIcon: "plus"
      onAction: addField.forceActiveFocus()
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
            readonly property bool editing: root.editingId === modelData.id

            Rectangle {
              Layout.preferredWidth: Math.round(64 * Style.uiScaleRatio)
              Layout.preferredHeight: Math.round(40 * Style.uiScaleRatio)
              radius: Math.round(6 * Style.uiScaleRatio)
              color: Qt.alpha(Color.mOnSurface, 0.06)
              clip: true

              Image {
                id: thumb
                anchors.fill: parent
                visible: status === Image.Ready
                source: row.modelData.image ? "file://" + row.modelData.image : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: 128
              }

              NIcon {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                icon: row.modelData.status === "pending" ? "loader" : "world"
                pointSize: Style.fontSizeL
                color: Qt.alpha(Color.mOnSurface, 0.42)
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NText {
                visible: !row.editing
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.title
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightSemiBold
                color: Color.mOnSurface
              }

              Field {
                id: renameField
                visible: row.editing
                Layout.fillWidth: true
                implicitHeight: Math.round(28 * Style.uiScaleRatio)
                onVisibleChanged: {
                  if (visible) {
                    text = row.modelData.title;
                    selectAll();
                    forceActiveFocus();
                  }
                }
                onAccepted: root.finishRename(row.modelData.id, text)
                Keys.onEscapePressed: root.editingId = ""
                onActiveFocusChanged: if (!activeFocus && visible) root.finishRename(row.modelData.id, text)
              }

              NText {
                visible: row.modelData.description !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.description
                pointSize: Style.fontSizeS
                color: Qt.alpha(Color.mOnSurface, 0.56)
              }

              NText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: Url.domainOf(row.modelData.url) + "  ·  " + Dates.isoDate(new Date(row.modelData.savedAt))
                pointSize: Style.fontSizeXS
                color: Qt.alpha(Color.mOnSurface, 0.42)
              }
            }

            // Shown on hover, while keyboard focus is inside, or while the delete
            // bubble is open (it lives outside the row, so hover/focus leave the row).
            // Never disabled: disabled buttons can't take Tab focus or answer the bubble.
            RowLayout {
              id: actions
              spacing: Math.round(2 * Style.uiScaleRatio)
              opacity: row.hovered || row.focusInside || bookmarkTrash.asking ? 1 : 0

              PillButton {
                icon: "copy"
                tooltipText: root.tr("bookmarks.copy")
                onClicked: root.mainInstance.copyText(row.modelData.url)
              }
              PillButton {
                icon: "refresh"
                tooltipText: root.tr("bookmarks.refresh")
                busy: row.modelData.status === "pending"
                onClicked: root.mainInstance.refreshBookmark(row.modelData.id)
              }
              PillButton {
                icon: "pencil"
                tooltipText: root.tr("bookmarks.rename")
                onClicked: root.editingId = row.modelData.id
              }
              ConfirmButton {
                id: bookmarkTrash
                icon: "trash"
                tooltipText: root.tr("bookmarks.delete")
                question: root.tr("bookmarks.confirm-delete")
                okText: root.tr("confirm.ok")
                cancelText: root.tr("confirm.cancel")
                onConfirmed: root.mainInstance.deleteBookmark(row.modelData.id)
                onOpened: root.asking++
                onClosed: root.asking = Math.max(0, root.asking - 1)
              }
            }

            // Clicking the row (outside the buttons) opens the link.
            TapHandler {
              enabled: !row.editing
              onTapped: root.mainInstance.openUrl(row.modelData.url)
            }
          }
        }
      }
    }

    Field {
      id: addField
      Layout.fillWidth: true
      placeholderText: root.feedback !== "" ? root.feedback : root.tr("bookmarks.add-placeholder")
      onAccepted: {
        const outcome = root.mainInstance.addBookmark(addField.text);
        if (outcome === "invalid") {
          addField.error = true;
          return;
        }
        addField.error = false;
        addField.text = "";
        root.feedback = root.tr(outcome === "replaced" ? "bookmarks.replaced" : "bookmarks.saved");
        feedbackTimer.restart();
      }
    }
  }
}
