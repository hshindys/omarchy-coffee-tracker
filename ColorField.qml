import QtQuick
import qs.Commons
import qs.Ui

// One row of colour choices: the label with the current value on the
// right, and a line of round swatches underneath.
//
// The first swatch is not one of the colours — it is the theme's own,
// drawn as whatever the chart would fall back to and marked with a small
// ring so it does not read as just another hue in the line. Choosing it
// writes an empty string, which is what "follow the theme" looks like in
// shell.json.
//
// The remaining nine are mid-tone hues rather than a light and a dark
// set: the panel's own accent is already the dark-or-light decision, so
// what is left for these is simply to stay visible on either.
Column {
  id: root

  property string label: ""
  property string value: ""
  property string themeLabel: "Theme"
  property color defaultColor: Color.accent
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal changed(string value)

  readonly property color dim: Qt.darker(foreground, 1.5)

  readonly property var swatches: [
    "", "#4dabf7", "#20c997", "#51cf66", "#fcc419",
    "#ff922b", "#ff6b6b", "#b197fc", "#f783ac"
  ]

  spacing: Style.space(6)

  Item {
    width: parent.width
    height: valueLabel.implicitHeight

    Text {
      id: valueLabel
      anchors.left: parent.left
      text: root.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      anchors.right: parent.right
      anchors.baseline: valueLabel.baseline
      text: root.value === "" ? root.themeLabel : String(root.value).toUpperCase()
      color: root.value === "" ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.value !== ""
    }
  }

  Row {
    spacing: Style.space(3)

    Repeater {
      model: root.swatches

      Item {
        id: chip
        required property var modelData

        readonly property string chipColor: String(modelData)
        readonly property bool selected: root.value.toLowerCase() === chipColor.toLowerCase()

        width: Style.space(20)
        height: Style.space(20)

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(14)
          height: Style.space(14)
          radius: width / 2
          color: chip.chipColor === "" ? root.defaultColor : chip.chipColor
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
        }

        // The ring sits outside the dot, so picking a colour never changes
        // the colour you are picking.
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(20)
          height: Style.space(20)
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: chip.selected
            ? root.foreground
            : (chipHover.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45) : "transparent")
        }

        // What marks the theme swatch as the theme swatch: a hollow centre
        // rather than a filled one, so it reads as "no colour of its own".
        Rectangle {
          anchors.centerIn: parent
          visible: chip.chipColor === ""
          width: Style.space(7)
          height: Style.space(7)
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
        }

        MouseArea {
          id: chipHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.changed(chip.chipColor)
        }
      }
    }
  }
}
