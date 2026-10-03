import QtQuick
import QtQuick.Shapes

// The day as a curve: how much caffeine is actually circulating, from
// midnight to a little past the moment it drops under the sleep threshold.
//
// The number in the header answers "how much is in me now". This answers
// the question that follows it — "and when does that stop mattering" —
// which a single number cannot, because the answer is a shape: every drink
// is a step up, and everything between the steps is the same exponential
// falling at the configured half-life.
//
// Past and future are drawn differently on purpose. Everything left of the
// now-marker happened; everything right of it is an extrapolation that
// assumes you drink nothing else, so it is the lighter, dashed half. A
// forecast that looks exactly like a measurement invites more trust than
// it has earned.
//
// The threshold line is the whole point of the picture. Where the curve
// crosses it is marked on the axis, because that crossing is the thing
// people open a caffeine tracker in the evening to find out.
Item {
  id: root

  // [{ t: epochMs, mg: real }], ascending. Sampled by the host widget.
  property var samples: []

  property real nowMs: 0
  property real startMs: 0
  property real endMs: 0

  property real threshold: 50
  property real peak: 100

  // Crossing of the threshold. Negative means it does not happen inside
  // the window, in which case nothing is marked.
  property real clearAtMs: -1
  property string clearAtLabel: ""
  property string thresholdLabel: ""
  property string midnightLabel: ""
  property string startLabel: ""
  property string endLabel: ""

  property color foreground: "white"
  property color dim: "gray"
  property color accent: "steelblue"
  // The crossing line, on its own so the panel can hand it a colour of the
  // user's choosing without that choice also recolouring the curve.
  property color thresholdColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.28)
  property color track: "#22ffffff"
  property string fontFamily: ""
  property real fontSize: 10

  // Room under the plot for the hour labels, and above it so a curve that
  // touches the peak is not clipped by the frame.
  readonly property real axisHeight: axisRow.implicitHeight + 4
  readonly property real plotHeight: Math.max(0, height - axisHeight)

  readonly property bool ready: samples.length > 1 && endMs > startMs && peak > 0

  // A window that starts at midnight and runs until the caffeine is gone
  // routinely crosses into the next day, and an axis reading 00:00 → 09:53
  // with no day boundary on it reads as ten hours instead of thirty-four.
  // The next midnight is drawn where it falls, which is the cheapest way to
  // say "this part is tomorrow".
  readonly property real midnightMs: {
    var day = new Date(startMs)
    day.setHours(24, 0, 0, 0)
    return day.getTime()
  }

  readonly property bool midnightVisible: ready && midnightMs > startMs && midnightMs < endMs

  function xFor(t) {
    return (t - startMs) / (endMs - startMs) * width
  }

  // A little headroom, so the day's highest point is a peak rather than a
  // line pressed flat against the top of the frame.
  readonly property real scaleTop: peak * 1.08

  function yFor(mg) {
    return plotHeight * (1 - Math.min(1, Math.max(0, mg / scaleTop)))
  }

  // The curve up to now, and the curve from now on, as two point lists.
  // The split sample is duplicated into both so the halves meet exactly
  // rather than leaving a gap at the seam.
  function pointsFor(fromMs, toMs) {
    var points = []
    for (var i = 0; i < samples.length; i++) {
      var sample = samples[i]
      if (sample.t < fromMs || sample.t > toMs) continue
      points.push(Qt.point(xFor(sample.t), yFor(sample.mg)))
    }
    return points
  }

  readonly property var pastPoints: ready ? pointsFor(startMs, nowMs) : []
  readonly property var futurePoints: ready ? pointsFor(nowMs, endMs) : []

  // Closed version of the past curve, dropped to the baseline at both ends,
  // so the area under it can be filled without the fill leaking upward.
  readonly property var pastArea: {
    if (pastPoints.length < 2) return []
    var area = pastPoints.slice()
    area.push(Qt.point(area[area.length - 1].x, plotHeight))
    area.push(Qt.point(area[0].x, plotHeight))
    return area
  }

  implicitHeight: 96

  // ---- Plot ------------------------------------------------------------
  Item {
    id: plot
    width: parent.width
    height: root.plotHeight

    // Baseline. Present even on an empty day, so the panel does not show a
    // blank rectangle where a chart belongs.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.track
    }

    // The threshold, and the label that says which number it is.
    Rectangle {
      id: thresholdLine
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      y: root.yFor(root.threshold)
      color: root.thresholdColor
      visible: root.ready

      Row {
        anchors.right: parent.right
        anchors.bottom: parent.top
        anchors.bottomMargin: 2
        spacing: 0

        Text {
          text: root.thresholdLabel
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }
      }
    }

    Shape {
      anchors.fill: parent
      visible: root.ready
      preferredRendererType: Shape.CurveRenderer

      // Area under what already happened. Tinted rather than solid: it sits
      // behind the threshold line and must not swallow it.
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)

        PathPolyline { path: root.pastArea }
      }

      // What happened.
      ShapePath {
        strokeWidth: 2
        strokeColor: root.accent
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        PathPolyline { path: root.pastPoints }
      }

      // What will happen if nothing else is drunk.
      ShapePath {
        strokeWidth: 2
        strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 3]

        PathPolyline { path: root.futurePoints }
      }
    }

    // The day boundary.
    Rectangle {
      visible: root.midnightVisible
      width: 1
      height: parent.height
      x: root.xFor(root.midnightMs)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    }

    // Now. The seam between measurement and forecast.
    Rectangle {
      visible: root.ready
      width: 1
      height: parent.height
      x: root.xFor(root.nowMs)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
    }

    // The crossing, marked where it lands rather than only named in the
    // header — a tick on the axis and a dot on the curve.
    Rectangle {
      id: crossing
      visible: root.ready && root.clearAtMs > root.nowMs && root.clearAtMs <= root.endMs
      width: 7
      height: 7
      radius: width / 2
      x: root.xFor(root.clearAtMs) - width / 2
      y: root.yFor(root.threshold) - height / 2
      color: root.accent
    }
  }

  // ---- Hour axis -------------------------------------------------------
  // Four times at most: where the window starts, where the day turns over,
  // where the curve crosses the threshold, and where the window ends. A
  // full hour ruler under a strip this size is a smear of digits, and these
  // are the only ones the curve is read for.
  //
  // They are placed left to right and each one gives way to the one before
  // it, so a crossing that lands next to midnight or hard against the right
  // edge drops a neighbour rather than printing on top of it. The crossing
  // outranks the window end, which is only ever "half an hour after the
  // crossing" anyway.
  Item {
    id: axisRow
    anchors.top: plot.bottom
    anchors.topMargin: 4
    width: parent.width
    implicitHeight: startTick.implicitHeight

    readonly property real gap: 8

    // Centred on its time, but never off either edge of the strip.
    function clampedX(timeMs, labelWidth) {
      return Math.max(0, Math.min(width - labelWidth, root.xFor(timeMs) - labelWidth / 2))
    }

    Text {
      id: startTick
      anchors.left: parent.left
      text: root.ready ? root.startLabel : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    // The crossing outranks everything except the window start: it is the
    // one time the curve is being read for, and a caffeine window that ends
    // just after midnight would otherwise lose it to the day label sitting
    // an hour to its left.
    Text {
      id: crossingTick
      x: axisRow.clampedX(root.clearAtMs, implicitWidth)
      visible: crossing.visible && x > startTick.width + axisRow.gap
      text: root.clearAtLabel
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: true
    }

    // Gives way to the crossing. The day boundary keeps its line in the
    // plot either way, so dropping the label costs the reading nothing.
    Text {
      id: midnightTick
      x: axisRow.clampedX(root.midnightMs, implicitWidth)
      visible: root.midnightVisible
        && x > startTick.width + axisRow.gap
        && !(crossingTick.visible
          && x < crossingTick.x + crossingTick.width + axisRow.gap
          && crossingTick.x < x + width + axisRow.gap)
      text: root.midnightLabel
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    // Last in line, and the least missed: the window ends half an hour
    // after the crossing by construction.
    Text {
      id: endTick
      anchors.right: parent.right
      visible: root.ready
        && !(crossingTick.visible && crossingTick.x + crossingTick.width + axisRow.gap > x)
        && !(midnightTick.visible && midnightTick.x + midnightTick.width + axisRow.gap > x)
        && x > startTick.width + axisRow.gap
      text: root.endLabel
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }
}
