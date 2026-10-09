import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Location
import "ui"
import "../utils/month.js" as Month
import "../utils/events.js" as Events

// Clock + selected day's events on the left, Monday-first month grid on the right.
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
  readonly property var cells: Month.monthGrid(year, month, today, root.mainInstance ? root.mainInstance.visibleEvents : CalendarService.events)
  readonly property var dayEvents: Events.eventsOn(root.mainInstance ? root.mainInstance.visibleEvents : CalendarService.events, selected)

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
        visible: root.mainInstance?.calendarReady && root.dayEvents.length === 0
        text: root.tr("calendar.nothing")
        pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.56)
      }

      Repeater {
        model: root.dayEvents

        ListRow {
          id: dayRow
          required property var modelData

          NText {
            text: dayRow.modelData.time || root.tr("calendar.all-day")
            family: Settings.data.ui.fontFixed
            pointSize: Style.fontSizeS
            color: Qt.alpha(Color.mOnSurface, 0.56)
          }

          NText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: dayRow.modelData.summary
            pointSize: Style.fontSizeM
            color: Color.mOnSurface
          }

          Item {
            implicitWidth: Math.round(24 * Style.uiScaleRatio)
            implicitHeight: implicitWidth

            EventDeleteButton {
              anchors.fill: parent
              visible: (dayRow.hovered || activeFocus || asking) && (root.mainInstance?.canDeleteEvent(dayRow.modelData.calendar) ?? false)
              pluginApi: root.pluginApi
              mainInstance: root.mainInstance
              uid: dayRow.modelData.uid
              calendar: dayRow.modelData.calendar
            }
          }
        }
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

          Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: height / 2
            color: modelData.date === root.selected ? Color.mOnSurface : (modelData.today ? Qt.alpha(Color.mOnSurface, 0.1) : (cellMouse.containsMouse ? Qt.alpha(Color.mOnSurface, 0.05) : "transparent"))

            NText {
              anchors.centerIn: parent
              text: modelData.day
              pointSize: Style.fontSizeS
              font.weight: modelData.today || modelData.date === root.selected ? Style.fontWeightSemiBold : Style.fontWeightRegular
              color: modelData.date === root.selected ? Color.mSurface : Color.mOnSurface
              opacity: modelData.inMonth ? 1 : 0.35
            }

            Rectangle {
              visible: modelData.hasEvents
              width: 4
              height: 4
              radius: 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 2
              color: modelData.date === root.selected ? Color.mSurface : Color.mPrimary
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
