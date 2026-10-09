import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Read-later links and captured notes.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  readonly property var links: mainInstance ? mainInstance.data.links.filter(l => !l.archived).slice().reverse() : []
  readonly property var notes: mainInstance ? mainInstance.data.notes.slice().reverse() : []

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  NScrollView {
    anchors.fill: parent
    anchors.margins: Style.marginM

    ColumnLayout {
      width: parent.width
      spacing: Style.marginS

      NText {
        text: root.tr("inbox.links")
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        visible: root.links.length === 0
        text: root.tr("inbox.no-links")
        color: Color.mOnSurfaceVariant
      }

      Repeater {
        model: root.links

        RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            text: modelData.url
            color: Color.mPrimary
          }

          NIconButton {
            icon: "external-link"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.open")
            onClicked: root.mainInstance.openUrl(modelData.url)
          }

          NIconButton {
            icon: "archive"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.archive")
            onClicked: root.mainInstance.archiveLink(modelData.id)
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      NText {
        text: root.tr("inbox.notes")
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        visible: root.notes.length === 0
        text: root.tr("inbox.no-notes")
        color: Color.mOnSurfaceVariant
      }

      Repeater {
        model: root.notes

        RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: modelData.text
            color: Color.mOnSurface
          }

          NIconButton {
            icon: "copy"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.copy")
            onClicked: root.mainInstance.copyText(modelData.text)
          }

          NIconButton {
            icon: "trash"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.delete")
            onClicked: root.mainInstance.deleteNote(modelData.id)
          }
        }
      }
    }
  }
}
