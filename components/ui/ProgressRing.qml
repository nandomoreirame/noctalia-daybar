import QtQuick 6.11
import QtQuick.Shapes 6.11
import qs.Commons

// Circular countdown ring: a faint full track and an arc for `progress` (0..1),
// drawn clockwise from 12 o'clock. Children are placed in a full-size center item.
Item {
  id: root

  property real progress: 0
  property real thickness: Math.round(6 * Style.uiScaleRatio)
  property color trackColor: Qt.alpha(Color.mOnSurface, 0.12)
  property color arcColor: Color.mPrimary
  property string accessibleName: ""
  default property alias content: center.data

  readonly property real ringRadius: Math.min(width, height) / 2 - thickness / 2
  readonly property real clamped: Math.min(1, Math.max(0, progress))
  // Animated copy of `clamped`; a Behavior cannot target a readonly property.
  property real shown: clamped

  implicitWidth: Math.round(160 * Style.uiScaleRatio)
  implicitHeight: implicitWidth

  Accessible.role: Accessible.ProgressBar
  Accessible.name: accessibleName

  // Smooths the one-second steps and the jump back to full on reset.
  Behavior on shown {
    NumberAnimation {
      duration: 250
    }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.trackColor
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.ringRadius
        radiusY: root.ringRadius
        startAngle: 0
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: root.shown > 0 ? root.arcColor : "transparent"
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.ringRadius
        radiusY: root.ringRadius
        startAngle: -90
        sweepAngle: 360 * root.shown
      }
    }
  }

  Item {
    id: center
    anchors.fill: parent
  }
}
