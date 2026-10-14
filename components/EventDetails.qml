import QtQuick 6.11
import QtQuick.Layouts 6.11
import qs.Commons
import qs.Widgets
import "ui"

// What an expanded calendar event shows below its row: the place, who is in it and a
// button to join the Meet call. Read from the event's .ics through Main on demand.
ColumnLayout {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string uid: ""
  property string calendar: ""

  readonly property var entry: mainInstance ? mainInstance.eventInfoCache[mainInstance.eventInfoKey(uid, calendar)] : undefined
  readonly property var info: entry && entry.info ? entry.info : null
  readonly property bool empty: !!info && info.people.length === 0 && info.location === "" && info.meetUrl === ""

  spacing: Math.round(6 * Style.uiScaleRatio)

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function load() {
    if (mainInstance && uid !== "")
      mainInstance.loadEventInfo(uid, calendar);
  }

  Component.onCompleted: load()
  // A finished read from an older generation, or a calendar reload, asks again.
  onEntryChanged: load()

  Connections {
    target: root.mainInstance
    function onEventInfoGenChanged() {
      root.load();
    }
  }

  NText {
    visible: !root.info
    text: root.entry && !root.entry.loading ? root.tr("events.details-none") : root.tr("events.details-loading")
    pointSize: Style.fontSizeS
    font.italic: true
    color: Qt.alpha(Color.mOnSurface, 0.42)
  }

  NText {
    visible: root.empty
    text: root.tr("events.details-none")
    pointSize: Style.fontSizeS
    font.italic: true
    color: Qt.alpha(Color.mOnSurface, 0.42)
  }

  RowLayout {
    visible: !!root.info && root.info.location !== ""
    Layout.fillWidth: true
    spacing: Math.round(6 * Style.uiScaleRatio)

    NIcon {
      icon: "map-pin"
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }

    NText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.info ? root.info.location : ""
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.75)
      Accessible.name: root.tr("events.location") + ": " + text
    }
  }

  RowLayout {
    visible: !!root.info && root.info.people.length > 0
    Layout.fillWidth: true
    spacing: Math.round(6 * Style.uiScaleRatio)

    NIcon {
      Layout.alignment: Qt.AlignTop
      icon: "users"
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }

    Flow {
      Layout.fillWidth: true
      spacing: Math.round(10 * Style.uiScaleRatio)
      Accessible.role: Accessible.List
      Accessible.name: root.tr("events.people")

      Repeater {
        model: root.info ? root.info.people : []

        NText {
          required property var modelData
          textFormat: Text.PlainText
          text: modelData.name + (modelData.status === "declined" ? " (" + root.tr("events.declined") + ")" : modelData.status === "tentative" ? " (" + root.tr("events.tentative") + ")" : "")
          pointSize: Style.fontSizeS
          color: Qt.alpha(Color.mOnSurface, modelData.status === "declined" ? 0.42 : 0.75)
          font.strikeout: modelData.status === "declined"
        }
      }
    }
  }

  PillButton {
    visible: !!root.info && root.info.meetUrl !== ""
    icon: "video"
    text: root.tr("events.join-meet")
    onClicked: root.mainInstance.openUrl(root.info.meetUrl)
  }
}
