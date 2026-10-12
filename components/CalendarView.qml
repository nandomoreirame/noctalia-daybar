import QtQuick 6.11
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Location
import "ui"
import "../utils/month.js" as Month
import "../utils/today.js" as Today

// Clock + selected day's events on the left, Sunday-first month grid on the right.
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property date now: new Date()
  // Changes only at midnight, so the month grid is not rebuilt on every clock tick.
  property date today: new Date()
  property int year: today.getFullYear()
  property int month: today.getMonth()
  property string selected: Qt.formatDate(today, "yyyy-MM-dd")
  readonly property var events: root.mainInstance ? root.mainInstance.visibleEvents : CalendarService.events
  readonly property string todayIso: Qt.formatDate(today, "yyyy-MM-dd")
  readonly property var cells: Month.monthGrid(year, month, today, events, root.mainInstance ? root.mainInstance.data.tasks : [])
  // Selected day: events, then tasks dated that day. Frozen while a delete bubble
  // is open so a data commit does not recreate the row under it.
  readonly property int maxRows: 5
  property int asking: 0
  property var frozenDay: []
  readonly property var liveDay: root.mainInstance ? Today.dayItems(events, root.mainInstance.data, selected, todayIso) : []
  readonly property var dayItems: asking > 0 ? frozenDay : liveDay
  onLiveDayChanged: if (asking === 0) frozenDay = liveDay
  onAskingChanged: if (asking === 0) frozenDay = liveDay

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function shift(delta) {
    const next = Month.shiftMonth(year, month, delta);
    year = next.year;
    month = next.month;
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: {
      const d = new Date();
      root.now = d;
      if (d.toDateString() !== root.today.toDateString())
        root.today = d;
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Math.round(14 * Style.uiScaleRatio)
    spacing: Math.round(18 * Style.uiScaleRatio)

    ColumnLayout {
      Layout.preferredWidth: parent.width * 0.38
      Layout.fillHeight: true
      spacing: Style.marginS

      NText {
        text: Qt.formatTime(root.now, "HH:mm")
        family: Settings.data.ui.fontFixed
        pointSize: Style.fontSizeXXXL * 1.6
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        text: root.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
        pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.56)
      }

      NText {
        visible: !root.mainInstance?.calendarReady
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.tr("calendar.not-configured")
        pointSize: Style.fontSizeS
        color: Color.mError
      }

      NText {
        visible: root.dayItems.length === 0
        text: root.selected === root.todayIso ? root.tr("calendar.nothing") : root.tr("calendar.nothing-day")
        pointSize: Style.fontSizeS
        font.italic: true
        color: Qt.alpha(Color.mOnSurface, 0.4)
      }

      Repeater {
        model: root.dayItems.slice(0, root.maxRows)

        ListRow {
          id: dayRow
          required property var modelData

          NText {
            text: dayRow.modelData.time || root.tr("calendar.all-day")
            family: Settings.data.ui.fontFixed
            pointSize: Style.fontSizeS
            color: dayRow.modelData.time ? Qt.alpha(Color.mOnSurface, 0.56) : Color.mPrimary
          }

          NIcon {
            visible: dayRow.modelData.kind === "task"
            icon: dayRow.modelData.done ? "square-check" : "checkbox"
            pointSize: Style.fontSizeS
            color: Qt.alpha(Color.mOnSurface, 0.42)
          }

          NText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: dayRow.modelData.title
            pointSize: Style.fontSizeM
            color: dayRow.modelData.done ? Qt.alpha(Color.mOnSurface, 0.42) : Color.mOnSurface
            font.strikeout: dayRow.modelData.done
          }

          Item {
            implicitWidth: Math.round(24 * Style.uiScaleRatio)
            implicitHeight: implicitWidth
            visible: dayRow.modelData.kind === "event" && (root.mainInstance?.canDeleteEvent(dayRow.modelData.calendar) ?? false)

            EventDeleteButton {
              anchors.fill: parent
              opacity: dayRow.hovered || dayRow.focusInside || asking ? 1 : 0
              pluginApi: root.pluginApi
              mainInstance: root.mainInstance
              uid: dayRow.modelData.uid
              calendar: dayRow.modelData.calendar
              onOpened: root.asking++
              onClosed: root.asking = Math.max(0, root.asking - 1)
            }
          }
        }
      }

      NText {
        visible: root.dayItems.length > root.maxRows
        Layout.leftMargin: Math.round(6 * Style.uiScaleRatio)
        text: root.tr("calendar.more").replace("{n}", root.dayItems.length - root.maxRows)
        pointSize: Style.fontSizeXS
        color: Qt.alpha(Color.mOnSurface, 0.42)
      }

      Item {
        Layout.fillHeight: true
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true

        NText {
          Layout.fillWidth: true
          text: new Date(root.year, root.month, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightSemiBold
          color: Color.mOnSurface
        }

        PillButton {
          icon: "chevron-left"
          tooltipText: root.tr("calendar.previous")
          onClicked: root.shift(-1)
        }

        PillButton {
          icon: "chevron-right"
          tooltipText: root.tr("calendar.next")
          onClicked: root.shift(1)
        }
      }

      GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 7
        rowSpacing: Style.marginXS
        columnSpacing: Style.marginXS

        Repeater {
          model: root.tr("calendar.weekdays").split(" ")

          NText {
            required property string modelData
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            pointSize: Style.fontSizeXS
            color: Qt.alpha(Color.mOnSurface, 0.42)
          }
        }

        Repeater {
          model: root.cells

          Item {
            id: cell
            required property var modelData
            readonly property bool isSelected: modelData.date === root.selected
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Circle sized to the cell's short side, leaving room for the dot below.
            Rectangle {
              id: dayCircle
              width: Math.max(0, Math.min(cell.width, cell.height - 8))
              height: width
              radius: width / 2
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -3
              color: cell.isSelected ? Color.mOnSurface : (cell.modelData.today ? Qt.alpha(Color.mOnSurface, 0.1) : (cellMouse.containsMouse ? Qt.alpha(Color.mOnSurface, 0.05) : "transparent"))

              NText {
                anchors.centerIn: parent
                text: cell.modelData.day
                pointSize: Style.fontSizeS
                font.weight: cell.modelData.today || cell.isSelected ? Style.fontWeightSemiBold : Style.fontWeightRegular
                color: cell.isSelected ? Color.mSurface : Color.mOnSurface
                opacity: cell.modelData.inMonth ? 1 : 0.35
              }
            }

            Rectangle {
              visible: cell.modelData.hasEvents || cell.modelData.hasTasks
              width: 4
              height: 4
              radius: 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: dayCircle.bottom
              anchors.topMargin: 2
              color: Color.mPrimary
            }

            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selected = modelData.date
            }
          }
        }
      }
    }
  }
}
