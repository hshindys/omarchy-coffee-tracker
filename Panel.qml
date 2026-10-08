import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The caffeine panel: the day's total as a number and a filling bar, then
// three tabs for the three sources that feed it — the machines on one, the
// leaves on one, the powders and cans on the third.
//
// The header and the right-hand column are deliberately outside the tabs.
// What you drank and how close you are to the ceiling is one number no
// matter where it came from; the tab only decides what you can add next.
// That is the whole reason all three sources live in one widget instead of
// several.
//
// Laid out wide rather than tall. The header spans the panel because the
// bar toward the daily ceiling is the one element that wants the full
// width; the settings sit behind a disclosure because they are set once and
// then in the way.
//
// The bar carries two fills. The outer fill is what was drunk today, the
// brighter inner fill is what is still in the bloodstream after the
// half-life has had its way with it — the same total means something very
// different at 09:00 and at 22:00.
//
// BarWidget.qml owns the log, the math, and the bar label; this panel is
// its face.
Panel {
  id: root
  moduleName: "io.github.philippbellia.coffee-tracker"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // "coffee" | "tea" | "energy". Not persisted: the panel opens on the
  // machines, which is where most days start.
  property string tab: "coffee"

  // Session-local as well — the panel should open compact every time, not
  // in whatever state a settings edit left it.
  property bool settingsOpen: false

  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // everything the bar identifies a panel by has to be that widget.
  readonly property var barIdentity: hostWidget || root
  readonly property var host: hostWidget

  // Every string in this panel goes through the host's I18n instance, so
  // the panel and the bar label are never in two different languages.
  function t(key) {
    if (!host) return ""
    return host.t.apply(host, arguments)
  }
  function decimal(value, digits) {
    return host ? host.i18n.decimal(value, digits) : String(value)
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.5)
  readonly property color accentColor: Style.selectedStateColor(contentForeground, Color.accent)
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property color trackColor: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.12)

  readonly property bool overLimit: host ? host.overLimit : false

  // Green under half the ceiling, yellow to 80 %, red past it — the level
  // colour the host computes from today's total, easing here into whatever
  // the bar, the fill and the pill are about to become.
  readonly property color fillColor: root.host ? root.host.levelColor : root.accentColor

  // Chart colours: whatever the user picked under Settings, or the theme's
  // own accent and a wash of the foreground when nothing has been picked.
  function chartColor(value, fallback) {
    var text = String(value || "").replace(/^\s+|\s+$/g, "")
    if (text === "") return fallback
    if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(text)) return text
    return fallback
  }

  readonly property color curveColor: chartColor(
    root.host ? root.host.chartCurveColor : "",
    root.overLimit ? root.urgentColor : root.accentColor)

  readonly property color thresholdLineColor: chartColor(
    root.host ? root.host.chartThresholdColor : "",
    Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.28))

  // The two defaults, held apart from the resolved colours above so the
  // settings row can show what "back to the theme" would give you even
  // while a custom colour is in force.
  readonly property color themeCurveColor: root.overLimit ? root.urgentColor : root.accentColor
  readonly property color themeThresholdColor: Qt.rgba(root.contentForeground.r,
    root.contentForeground.g, root.contentForeground.b, 0.28)

  // Energy reads as the same colour at half strength — one palette, two
  // materials, so a stacked column still says "caffeine" first. Tea sits
  // between the two: brewed like coffee, dosed like a label.
  function teaTint(base) {
    return Qt.rgba(base.r, base.g, base.b, 0.7)
  }

  function energyTint(base) {
    return Qt.rgba(base.r, base.g, base.b, 0.45)
  }

  // Newest first: the drink you just logged is the one you might want to
  // take back, so it sits where the eye lands.
  readonly property var todayReversed: {
    var src = host ? host.todayEntries : []
    var out = []
    for (var i = src.length - 1; i >= 0; i--) out.push(src[i])
    return out
  }

  readonly property bool weekHasCoffee: {
    var weeks = host ? host.weekTotals : []
    for (var i = 0; i < weeks.length; i++) if (weeks[i].coffeeMg > 0) return true
    return false
  }

  readonly property bool weekHasEnergy: {
    var weeks = host ? host.weekTotals : []
    for (var i = 0; i < weeks.length; i++) if (weeks[i].energyMg > 0) return true
    return false
  }

  readonly property bool weekHasTea: {
    var weeks = host ? host.weekTotals : []
    for (var i = 0; i < weeks.length; i++) if (weeks[i].teaMg > 0) return true
    return false
  }

  function open() {
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function persist(values) {
    if (host) host.persistSettings(values)
  }

  // Slider handlers hand back whatever the drag produced; a value that is not
  // a finite number is a control mid-construction, not a user decision.
  function persistNumber(key, value) {
    if (!isFinite(value)) return
    var values = {}
    values[key] = value
    persist(values)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(820))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: limitField.field.activeFocus || halfLifeField.field.activeFocus
        || sleepField.field.activeFocus || doseField.field.activeFocus
        || holyMgField.field.activeFocus || holyMlField.field.activeFocus
        || nightStartField.field.activeFocus

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.host) root.host.addDrink(root.host.defaultDrink)
      onTextKey: function(t) {
        if (!root.host) return
        var key = t.toLowerCase()
        if (key === "u") root.host.undoLast()
        else if (key === "e") root.host.addDrink(root.host.defaultDrink)
        else if (key === "h") root.host.addDrinkId("holy-1")
        else if (key === "m") root.host.cycleMethod()
        else if (key === "1") root.tab = "coffee"
        else if (key === "2") root.tab = "tea"
        else if (key === "3") root.tab = "energy"
        else if (key === ",") root.settingsOpen = !root.settingsOpen
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: column.width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(14)

          // ---- Header. Full width, because the bar toward the ceiling is
          //      the one element that earns it — and because it is the one
          //      thing all three tabs feed.
          Item {
            width: parent.width
            height: Math.max(heroIconSlot.height, heroLabels.implicitHeight, headerStats.implicitHeight)

            // The cup. The glyph and the steam above it live in one slot so
            // that when a drink is logged a single thing moves: the slot
            // bounces for as long as the host keeps the pulse alive, and the
            // wisps lift out of the top of the glyph's own box and fade.
            // Nothing new is drawn once the two seconds are up.
            Item {
              id: heroIconSlot
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: heroIcon.implicitWidth
              height: heroIcon.implicitHeight

              readonly property int cupPulse: root.host ? root.host.cupPulse : 0
              readonly property bool steaming: root.host ? root.host.cupAnimating : false

              onCupPulseChanged: if (cupPulse > 0) heroBounce.restart()

              Text {
                id: heroIcon
                anchors.centerIn: parent
                text: root.tab === "energy" ? "󱐋" : (root.tab === "tea" ? "󰶞" : (root.host ? root.host.methodIcon : "󱂟"))
                color: root.host && root.host.todayEntries.length > 0 ? root.fillColor : root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.displayLarge

                Behavior on color { ColorAnimation { duration: 420; easing.type: Easing.InOutQuad } }
              }

              // Three wisps on the same loop, each starting a quarter of a
              // second after the last, so they rise as separate trails
              // rather than as one flicker. `progress` is the only thing
              // animated: position and opacity are derived from it, which
              // leaves the bindings intact and the wisps back at the rim
              // the moment the loop turns over.
              Item {
                id: steam
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * 0.55
                visible: heroIconSlot.steaming

                Repeater {
                  model: 3

                  Rectangle {
                    id: wisp
                    required property int index

                    property real progress: 0

                    width: Math.max(2, Math.round(steam.height * 0.16))
                    height: steam.height * 0.5
                    radius: width / 2
                    x: steam.width * (0.30 + index * 0.20) - width / 2
                    y: steam.height * (1 - progress)
                    opacity: Math.sin(Math.max(0, Math.min(1, progress)) * Math.PI) * 0.8
                    color: root.fillColor

                    SequentialAnimation {
                      id: wispLoop
                      running: heroIconSlot.steaming
                      loops: Animation.Infinite
                      // Stopping mid-cycle leaves `progress` wherever the
                      // wisp happened to be. Zeroing it on the way out means
                      // the next cup starts from the rim rather than showing
                      // a stray trail for the length of the opening pause.
                      onRunningChanged: if (!running) wisp.progress = 0
                      PauseAnimation { duration: wisp.index * 240 }
                      NumberAnimation {
                        target: wisp
                        property: "progress"
                        from: 0
                        to: 1
                        duration: 1300
                        easing.type: Easing.OutQuad
                      }
                      PropertyAction { target: wisp; property: "progress"; value: 0 }
                    }
                  }
                }
              }

              SequentialAnimation {
                id: heroBounce
                loops: 3
                NumberAnimation { target: heroIconSlot; property: "scale"; to: 1.14; duration: 190; easing.type: Easing.OutBack }
                NumberAnimation { target: heroIconSlot; property: "scale"; to: 1.0; duration: 430; easing.type: Easing.InOutSine }
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIconSlot.right
              anchors.leftMargin: Style.space(14)
              anchors.right: headerStats.left
              anchors.rightMargin: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(5)

                Text {
                  id: heroNumber
                  text: root.host ? root.host.todayMg : 0
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }

                Text {
                  anchors.baseline: heroNumber.baseline
                  text: "mg"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
              }

              Text {
                width: parent.width
                text: root.host
                  ? (root.t("panel.today") + " · " + root.host.sourceSummary
                    + " · " + root.host.formatVolume(root.host.todayMl)).toUpperCase()
                  : ""
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            // The two read-outs the bar cannot carry, plus the share pill.
            Row {
              id: headerStats
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(22)

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: root.t("panel.roomLeft")
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Text {
                  text: {
                    if (!root.host) return "—"
                    if (root.overLimit) return root.t("count.cup.zero")
                    var n = root.host.remainingCups
                    return n === 1 ? root.t("count.cup.one") : root.t("count.cup.other", n)
                  }
                  color: root.overLimit ? root.urgentColor : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: root.host ? root.t("panel.under", root.host.sleepThreshold) : ""
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Text {
                  text: root.host ? root.host.clearAtLabel : "—"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }

              BorderSurface {
                id: sharePill
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: shareText.implicitWidth + Style.space(14)
                implicitHeight: shareText.implicitHeight + Style.space(7)
                color: "transparent"
                radius: Style.cornerRadius
                // The pill is the percentage of the ceiling the bar is
                // filling toward, so it wears the same level colour the bar
                // does — and keeps the neutral ring until there is
                // something to be a percentage of.
                borderSpec: Border.flat(root.host && root.host.todayEntries.length > 0
                  ? root.fillColor
                  : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.35),
                  Math.max(1, Style.spacing.hairline))

                Text {
                  id: shareText
                  anchors.centerIn: parent
                  text: root.host && root.host.dailyLimit > 0
                    ? Math.round(root.host.todayMg / root.host.dailyLimit * 100) + " %"
                    : "0 %"
                  color: root.host && root.host.todayEntries.length > 0
                    ? root.fillColor
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true

                  Behavior on color { ColorAnimation { duration: 420; easing.type: Easing.InOutQuad } }
                }
              }
            }
          }

          // ---- The bar toward the daily recommendation.
          Column {
            width: parent.width
            spacing: Style.space(7)

            Item {
              width: parent.width
              height: Style.space(12)

              Rectangle {
                id: limitTrack
                anchors.fill: parent
                radius: height / 2
                color: root.trackColor
              }

              // Consumed today.
              Rectangle {
                anchors.left: limitTrack.left
                anchors.verticalCenter: limitTrack.verticalCenter
                height: limitTrack.height
                radius: limitTrack.radius
                width: limitTrack.width * (root.host ? root.host.todayProgress : 0)
                color: root.energyTint(root.fillColor)

                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                // Longer than the width, so the fill arrives first and the
                // hue follows it across the threshold instead of arriving
                // together as a cut.
                Behavior on color { ColorAnimation { duration: 420; easing.type: Easing.InOutQuad } }
              }

              // Still circulating, after the half-life has taken its cut.
              Rectangle {
                anchors.left: limitTrack.left
                anchors.verticalCenter: limitTrack.verticalCenter
                height: limitTrack.height
                radius: limitTrack.radius
                width: limitTrack.width * (root.host ? root.host.activeProgress : 0)
                color: root.fillColor

                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 420; easing.type: Easing.InOutQuad } }
              }
            }

            Item {
              width: parent.width
              height: legendLeft.implicitHeight

              Text {
                id: legendLeft
                anchors.left: parent.left
                text: {
                  if (!root.host) return ""
                  var summary = root.host.bucketSummary()
                  if (summary)
                    return root.t("panel.inBody", root.host.activeMg) + "  ·  " + summary
                  return root.t("panel.inBody", root.host.activeMg)
                }
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                text: {
                  if (!root.host) return ""
                  if (root.overLimit)
                    return root.t("panel.overGoal", root.host.todayMg - root.host.dailyLimit)
                  return root.t("panel.remainingOf", root.host.remainingMg, root.host.dailyLimit)
                }
                color: root.overLimit ? root.urgentColor : root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ---- Body: what you can add, next to what you already did.
          Row {
            id: body
            width: parent.width
            spacing: Style.space(20)

            readonly property real colWidth: (width - spacing) / 2

            Column {
              id: leftColumn
              width: body.colWidth
              spacing: Style.space(10)

              // ---- Tabs. The one control that swaps this column; the rest
              //      of the panel is shared on purpose.
              Row {
                id: tabRow
                spacing: Style.space(4)

                Repeater {
                  model: [
                    { id: "coffee", label: root.t("tab.coffee"), icon: "󰅶" },
                    { id: "tea", label: root.t("tab.tea"), icon: "󰶞" },
                    { id: "energy", label: root.t("tab.energy"), icon: "󱐋" }
                  ]

                  Item {
                    id: tabItem
                    required property var modelData

                    readonly property bool selected: root.tab === modelData.id
                    readonly property color tint: selected ? root.contentForeground : root.dim

                    width: tabContent.implicitWidth + Style.space(20)
                    height: Style.space(30)

                    Rectangle {
                      anchors.fill: parent
                      anchors.bottomMargin: Style.space(3)
                      radius: Style.cornerRadius
                      color: tabMouse.containsMouse && !tabItem.selected
                        ? Style.hoverFillFor(root.contentForeground, Color.accent)
                        : "transparent"
                    }

                    Row {
                      id: tabContent
                      anchors.centerIn: parent
                      anchors.verticalCenterOffset: -Style.space(2)
                      spacing: Style.space(6)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabItem.modelData.icon
                        color: tabItem.tint
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.icon
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabItem.modelData.label
                        color: tabItem.tint
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: tabItem.selected
                      }
                    }

                    // The underline is the selection; a filled chip here
                    // would fight the Zubereitung chips right underneath it.
                    Rectangle {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      height: Style.space(2)
                      radius: height / 2
                      color: tabItem.selected ? root.accentColor : "transparent"

                      Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    MouseArea {
                      id: tabMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.tab = tabItem.modelData.id
                    }
                  }
                }
              }

              // ================= Kaffee =================
              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: root.tab === "coffee"

                PanelSectionHeader {
                  text: root.t("section.brewMethod")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                // Four chips are wider than the column they live in, and a
                // Row does not wrap — left alone they run past the column
                // edge and land on top of the log beside it. So the row
                // measures itself against the column and shrinks to fit it,
                // staying at full size whenever there is room for that.
                Item {
                  id: brewRowFrame
                  width: parent.width
                  height: Math.round(brewGroup.implicitHeight * brewGroup.fitScale)

                  ButtonGroup {
                    id: brewGroup
                    focusable: false
                    readonly property real fitScale: implicitWidth > 0
                      ? Math.min(1, brewRowFrame.width / implicitWidth)
                      : 1
                    scale: fitScale
                    transformOrigin: Item.TopLeft
                    value: root.host ? root.host.method : "portafilter"
                    foreground: root.contentForeground
                    background: root.bar ? root.bar.background : Color.background
                    fontFamily: root.contentFontFamily
                    options: [
                      { value: "portafilter", label: root.t("method.portafilter"), icon: "󱂟", tooltip: root.t("method.portafilter.tooltip") },
                      { value: "chemex", label: root.t("method.chemex"), icon: "󱜼", tooltip: root.t("method.chemex.tooltip") },
                      { value: "french", label: root.t("method.french"), icon: "󰙚", tooltip: root.t("method.french.tooltip") },
                      { value: "turkish", label: root.t("method.turkish"), icon: "󰛊", tooltip: root.t("method.turkish.tooltip") }
                    ]
                    onChanged: function(v) { if (root.host) root.host.setMethod(v) }
                  }
                }

                Text {
                  width: parent.width
                  text: {
                    if (!root.host) return ""
                    // Every method but the portafilter is priced per volume,
                    // so they all read the same ratio / yield summary.
                    if (root.host.method !== "portafilter")
                      return root.t("brew.filterSummary",
                        root.decimal(root.host.filterRatioPer100, 1),
                        Math.round(root.host.filterYield * 100),
                        root.host.mgPerFilterCup)
                    return root.t("brew.espressoSummary",
                      root.host.doseGrams,
                      Math.round(root.host.espressoYield * 100),
                      root.host.mgPerShot)
                  }
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                PanelSectionHeader {
                  text: root.t("section.logCup")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Grid {
                  id: coffeeGrid
                  width: parent.width
                  columns: 2
                  columnSpacing: Style.space(10)
                  rowSpacing: Style.space(10)

                  readonly property real cellWidth: (width - columnSpacing) / 2

                  Repeater {
                    model: root.host ? root.host.drinks : []

                    DrinkCard {
                      required property var modelData
                      width: coffeeGrid.cellWidth
                      iconText: modelData.icon
                      title: modelData.name
                      subtitle: root.host
                        ? root.host.formatVolume(root.host.volumeFor(modelData))
                          + " · " + root.host.caffeineFor(modelData) + " mg"
                        : ""
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: if (root.host) root.host.addDrink(modelData)
                    }
                  }
                }
              }

              // ================= Tee =================
              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: root.tab === "tea"

                PanelSectionHeader {
                  text: root.t("section.logCup")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Grid {
                  id: teaGrid
                  width: parent.width
                  columns: 2
                  columnSpacing: Style.space(10)
                  rowSpacing: Style.space(10)

                  readonly property real cellWidth: (width - columnSpacing) / 2

                  Repeater {
                    model: root.host ? root.host.teaDrinks : []

                    DrinkCard {
                      required property var modelData
                      width: teaGrid.cellWidth
                      iconText: modelData.icon
                      title: modelData.name
                      subtitle: root.host
                        ? root.host.formatVolume(root.host.volumeFor(modelData))
                          + " · " + root.host.caffeineFor(modelData) + " mg"
                        : ""
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: if (root.host) root.host.addDrink(modelData)
                    }
                  }
                }

                Text {
                  width: parent.width
                  text: root.t("tea.note")
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              // ================= Cold drinks =================
              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: root.tab === "energy"

                PanelSectionHeader {
                  text: root.t("section.cans")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Grid {
                  id: canGrid
                  width: parent.width
                  columns: 2
                  columnSpacing: Style.space(10)
                  rowSpacing: Style.space(10)

                  readonly property real cellWidth: (width - columnSpacing) / 2

                  Repeater {
                    model: root.host ? root.host.canDrinks : []

                    DrinkCard {
                      required property var modelData
                      width: canGrid.cellWidth
                      iconText: modelData.icon
                      title: modelData.name
                      subtitle: root.host
                        ? root.host.formatVolume(modelData.ml)
                          + " · " + root.host.caffeineFor(modelData) + " mg"
                        : ""
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: if (root.host) root.host.addDrink(modelData)
                    }
                  }
                }

                Text {
                  width: parent.width
                  text: root.t("cans.note")
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }

            Column {
              id: rightColumn
              width: body.colWidth
              spacing: Style.space(10)

              // ---- Today's log, every source in one list. Every drink is
              //      removable, because a tracker you cannot correct is a
              //      tracker you stop trusting.
              Item {
                width: parent.width
                height: Math.max(todayHeader.implicitHeight, todayActions.implicitHeight)

                PanelSectionHeader {
                  id: todayHeader
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.t("section.today")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Row {
                  id: todayActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  PanelActionButton {
                    iconText: "󰕌"
                    tooltipText: root.t("log.undoLast")
                    enabled: root.todayReversed.length > 0
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: if (root.host) root.host.undoLast()
                  }

                  PanelActionButton {
                    iconText: "󰜉"
                    tooltipText: root.t("log.clearToday")
                    enabled: root.todayReversed.length > 0
                    foreground: root.contentForeground
                    hoverColor: root.urgentColor
                    fontFamily: root.contentFontFamily
                    onClicked: if (root.host) root.host.clearToday()
                  }
                }
              }

              Text {
                width: parent.width
                visible: root.todayReversed.length === 0
                text: root.t("log.empty")
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Column {
                width: parent.width
                spacing: Style.space(2)
                visible: root.todayReversed.length > 0

                Repeater {
                  model: root.todayReversed

                  Item {
                    id: logRow
                    required property var modelData

                    readonly property bool isEnergy: modelData.source === "energy"

                    width: parent.width
                    height: Math.max(Style.space(26), logLeft.implicitHeight)

                    Rectangle {
                      anchors.fill: parent
                      anchors.leftMargin: -Style.space(6)
                      anchors.rightMargin: -Style.space(6)
                      radius: Style.cornerRadius
                      color: rowMouse.containsMouse
                        ? Style.hoverFillFor(root.contentForeground, Color.accent)
                        : "transparent"
                    }

                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.NoButton
                    }

                    Row {
                      id: logLeft
                      anchors.left: parent.left
                      anchors.right: logRight.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.host ? root.host.formatTime(logRow.modelData.t) : ""
                        color: root.dim
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                          var d = root.host ? root.host.drinkById(logRow.modelData.id) : null
                          return d ? d.icon : (logRow.isEnergy ? "󱐋" : "󰅶")
                        }
                        // Energy keeps the tint it has everywhere else, and
                        // tea carries its own leaf, so the list reads by
                        // source without a legend.
                        color: logRow.isEnergy ? root.accentColor : root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.host ? root.host.entryName(logRow.modelData) : ""
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                    }

                    Row {
                      id: logRight
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: logRow.modelData.mg + " mg"
                        color: root.dim
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      PanelActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconText: "󰅖"
                        tooltipText: root.t("log.deleteDrink")
                        size: Style.space(20)
                        fontSize: Style.font.iconSmall
                        foreground: root.contentForeground
                        hoverColor: root.urgentColor
                        fontFamily: root.contentFontFamily
                        onClicked: if (root.host) root.host.removeEntryAt(logRow.modelData.t)
                      }
                    }
                  }
                }
              }

              PanelSeparator { foreground: root.contentForeground }

              // ---- The decay curve. The header says how much is in you
              //      and when that drops under the threshold; this says how
              //      it got there and how steeply it is coming down, which
              //      is the difference between "still 120 mg" at 14:00 and
              //      the same 120 mg at 22:00.
              Item {
                width: parent.width
                height: Math.max(curveHeader.implicitHeight, curveLegend.implicitHeight)

                PanelSectionHeader {
                  id: curveHeader
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.t("section.curve")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Text {
                  id: curveLegend
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.host ? root.t("curve.legend", root.host.activeMg) : ""
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              DecayChart {
                width: parent.width
                height: Style.space(104)

                samples: root.host ? root.host.decayCurve : []
                nowMs: root.host ? root.host.now : 0
                startMs: root.host ? root.host.curveStartMs : 0
                endMs: root.host ? root.host.curveEndMs : 0
                threshold: root.host ? root.host.sleepThreshold : 50
                peak: root.host ? root.host.curvePeak : 100
                clearAtMs: root.host ? root.host.clearAtMs : -1
                clearAtLabel: root.host ? root.host.clearAtLabel : ""
                thresholdLabel: root.host ? root.t("curve.threshold", root.host.sleepThreshold) : ""
                // The window regularly runs past midnight; naming the day it
                // turns into beats a second "00:00" on the same axis.
                midnightLabel: root.host
                  ? root.t("day.short." + new Date(root.host.curveStartMs + 86400000).getDay())
                  : ""
                startLabel: root.host ? root.host.formatTime(root.host.curveStartMs) : ""
                endLabel: root.host ? root.host.formatTime(root.host.curveEndMs) : ""

                foreground: root.contentForeground
                dim: root.dim
                accent: root.curveColor
                thresholdColor: root.thresholdLineColor
                track: root.trackColor
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
              }

              PanelSeparator { foreground: root.contentForeground }

              // ---- The week, stacked by source. Context for whether today
              //      is a spike or a habit, and for which of the two is
              //      driving it; the hairline is the daily ceiling.
              PanelSectionHeader {
                text: root.t("section.week")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Row {
                id: weekRow
                width: parent.width
                spacing: Style.space(6)

                readonly property real colWidth: (width - spacing * 6) / 7
                readonly property real plotHeight: Style.space(52)

                function barHeight(mg) {
                  var peak = root.host ? root.host.weekPeak : 1
                  if (peak <= 0) return 0
                  return weekRow.plotHeight * Math.min(1, mg / peak)
                }

                Repeater {
                  model: root.host ? root.host.weekTotals : []

                  Column {
                    id: weekCol
                    required property var modelData

                    readonly property bool over: root.host && modelData.mg > root.host.dailyLimit
                    readonly property color baseColor: {
                      if (over) return root.urgentColor
                      return modelData.today
                        ? root.accentColor
                        : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.35)
                    }

                    width: weekRow.colWidth
                    spacing: Style.space(4)

                    Item {
                      width: parent.width
                      height: weekRow.plotHeight

                      // Empty day: a hairline on the floor rather than
                      // nothing, so the column still reads as a column.
                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        visible: weekCol.modelData.mg === 0
                        height: Style.spacing.hairline
                        color: root.trackColor
                      }

                      Rectangle {
                        id: coffeeSegment
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        radius: Math.min(Style.space(3), width / 2)
                        height: weekRow.barHeight(weekCol.modelData.coffeeMg)
                        color: weekCol.baseColor

                        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                      }

                      Rectangle {
                        id: teaSegment
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: coffeeSegment.height
                        radius: Math.min(Style.space(3), width / 2)
                        height: weekRow.barHeight(weekCol.modelData.teaMg)
                        color: root.teaTint(weekCol.baseColor)

                        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                      }

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: coffeeSegment.height + teaSegment.height
                        radius: Math.min(Style.space(3), width / 2)
                        height: weekRow.barHeight(weekCol.modelData.energyMg)
                        color: root.energyTint(weekCol.baseColor)

                        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                      }

                      // The daily ceiling, drawn across every column at the
                      // same height so the row reads as one chart.
                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Style.spacing.hairline
                        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.3)
                        y: {
                          var peak = root.host ? root.host.weekPeak : 1
                          var limit = root.host ? root.host.dailyLimit : 400
                          if (peak <= 0) return weekRow.plotHeight
                          return weekRow.plotHeight * (1 - Math.min(1, limit / peak))
                        }
                      }
                    }

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      // Qt would format this in the session locale, which is
                      // not necessarily the language the panel is speaking.
                      text: root.t("day.short." + new Date(weekCol.modelData.day).getDay())
                      color: weekCol.modelData.today ? root.contentForeground : root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: weekCol.modelData.today
                    }
                  }
                }
              }

              // Only worth explaining once there is something to explain,
              // and only the sources that actually appear in the strip.
              Row {
                visible: root.weekHasCoffee || root.weekHasTea || root.weekHasEnergy
                spacing: Style.space(12)

                Row {
                  visible: root.weekHasCoffee
                  spacing: Style.space(5)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    color: root.accentColor
                  }

                  Text {
                    text: root.t("legend.coffee")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  visible: root.weekHasTea
                  spacing: Style.space(5)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    color: root.teaTint(root.accentColor)
                  }

                  Text {
                    text: root.t("legend.tea")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  visible: root.weekHasEnergy
                  spacing: Style.space(5)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    color: root.energyTint(root.accentColor)
                  }

                  Text {
                    text: root.t("legend.energy")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ---- Settings, behind a disclosure. They are set once and then
          //      only ever in the way; the closed row still states what the
          //      model is currently doing.
          Item {
            id: settingsHeader
            width: parent.width
            height: Style.space(26)

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -Style.space(6)
              anchors.rightMargin: -Style.space(6)
              radius: Style.cornerRadius
              color: settingsMouse.containsMouse
                ? Style.hoverFillFor(root.contentForeground, Color.accent)
                : "transparent"
            }

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.settingsOpen ? "󰅃" : "󰅀"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("section.settings")
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.settingsOpen
              text: root.host
                ? root.t("settings.summary", root.host.dailyLimit,
                  root.decimal(root.host.beanMgPerGram, 1), root.host.holyMgPerServing)
                : ""
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }

          Row {
            id: settingsBody
            width: parent.width
            spacing: Style.space(20)
            visible: root.settingsOpen

            readonly property real colWidth: (width - spacing * 2) / 3

            Column {
              width: settingsBody.colWidth
              spacing: Style.space(10)

              PanelSectionHeader {
                text: root.t("section.goalDecay")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Grid {
                id: goalGrid
                width: parent.width
                columns: 2
                columnSpacing: Style.space(10)
                rowSpacing: Style.space(10)

                readonly property real cellWidth: (width - columnSpacing) / 2

                SettingField {
                  id: limitField
                  label: root.t("settings.dailyLimit")
                  from: 50
                  to: 2000
                  stepSize: 10
                  value: root.host ? root.host.dailyLimit : 400
                  fieldWidth: goalGrid.cellWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("dailyLimit", v) }
                }

                SettingField {
                  id: halfLifeField
                  label: root.t("settings.halfLife")
                  from: 1
                  to: 12
                  value: root.host ? Math.round(root.host.halfLifeHours) : 5
                  fieldWidth: goalGrid.cellWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("halfLifeHours", v) }
                }

                SettingField {
                  id: sleepField
                  label: root.t("settings.residual")
                  from: 5
                  to: 400
                  stepSize: 5
                  value: root.host ? root.host.sleepThreshold : 50
                  fieldWidth: goalGrid.cellWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("sleepThreshold", v) }
                }

                SettingField {
                  id: doseField
                  label: root.t("settings.dose")
                  from: 5
                  to: 40
                  value: root.host ? root.host.doseGrams : 18
                  fieldWidth: goalGrid.cellWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("doseGrams", v) }
                }
              }

              Text {
                width: parent.width
                text: root.t("settings.efsaNote")
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Column {
              width: settingsBody.colWidth
              spacing: Style.space(10)

              PanelSectionHeader {
                text: root.t("section.beanExtraction")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Column {
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: beanLabel.implicitHeight

                  Text {
                    id: beanLabel
                    anchors.left: parent.left
                    text: root.t("settings.beanCaffeine")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.right: parent.right
                    text: root.decimal(beanSlider.liveValue, 1) + " mg/g"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                PanelSlider {
                  id: beanSlider
                  width: parent.width
                  bar: root.bar
                  minimum: 6
                  maximum: 20
                  step: 0.5
                  value: root.host ? root.host.beanMgPerGram : 12
                  onReleased: function(v) { root.persistNumber("beanMgPerGram", Math.round(v * 2) / 2) }
                }

                Text {
                  width: parent.width
                  text: root.t("settings.beanNote")
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              // Only the machine that is actually selected shows its knobs —
              // the switch in the tab is a mode, not a filter on a form.
              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.host ? root.host.method === "portafilter" : true

                Item {
                  width: parent.width
                  height: espressoLabel.implicitHeight

                  Text {
                    id: espressoLabel
                    anchors.left: parent.left
                    text: root.t("settings.espressoYield")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.right: parent.right
                    text: Math.round(espressoSlider.liveValue) + " % · ≈ "
                      + Math.round((root.host ? root.host.doseGrams * root.host.beanMgPerGram : 216)
                        * espressoSlider.liveValue / 100) + " mg"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                PanelSlider {
                  id: espressoSlider
                  width: parent.width
                  bar: root.bar
                  minimum: 20
                  maximum: 100
                  step: 1
                  integer: true
                  value: root.host ? Math.round(root.host.espressoYield * 100) : 65
                  onReleased: function(v) { root.persistNumber("espressoYield", Math.round(v)) }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.host ? root.host.method !== "portafilter" : false

                Item {
                  width: parent.width
                  height: ratioLabel.implicitHeight

                  Text {
                    id: ratioLabel
                    anchors.left: parent.left
                    text: root.t("settings.brewRatio")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.right: parent.right
                    text: root.decimal(ratioSlider.liveValue, 1) + " g / 100 ml"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                PanelSlider {
                  id: ratioSlider
                  width: parent.width
                  bar: root.bar
                  minimum: 3
                  maximum: 12
                  step: 0.25
                  value: root.host ? root.host.filterRatioPer100 : 6
                  onReleased: function(v) { root.persistNumber("filterRatioPer100", Math.round(v * 4) / 4) }
                }

                Item {
                  width: parent.width
                  height: filterYieldLabel.implicitHeight

                  Text {
                    id: filterYieldLabel
                    anchors.left: parent.left
                    text: root.t("settings.filterYield")
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.right: parent.right
                    text: Math.round(filterYieldSlider.liveValue) + " % · ≈ "
                      + Math.round((root.host ? 2 * root.host.filterRatioPer100 * root.host.beanMgPerGram : 144)
                        * filterYieldSlider.liveValue / 100) + " mg"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                PanelSlider {
                  id: filterYieldSlider
                  width: parent.width
                  bar: root.bar
                  minimum: 20
                  maximum: 100
                  step: 1
                  integer: true
                  value: root.host ? Math.round(root.host.filterYield * 100) : 90
                  onReleased: function(v) { root.persistNumber("filterYield", Math.round(v)) }
                }
              }
            }

            Column {
              width: settingsBody.colWidth
              spacing: Style.space(10)

              PanelSectionHeader {
                text: root.t("section.holyServing")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Grid {
                id: holyGridSettings
                width: parent.width
                columns: 2
                columnSpacing: Style.space(10)
                rowSpacing: Style.space(10)

                readonly property real cellWidth: (width - columnSpacing) / 2

                SettingField {
                  id: holyMgField
                  label: root.t("settings.holyCaffeine")
                  from: 10
                  to: 500
                  stepSize: 10
                  value: root.host ? root.host.holyMgPerServing : 200
                  fieldWidth: holyGridSettings.cellWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("holyMgPerServing", v) }
                }

                SettingField {
                  id: holyMlField
                  label: root.t("settings.holyWater")
                  from: 100
                  to: 1000
                  stepSize: 50
                  value: root.host ? root.host.holyMlPerServing : 500
                  fieldWidth: holyGridSettings.cellWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("holyMlPerServing", v) }
                }
              }

              Text {
                width: parent.width
                text: root.t("settings.holyNote")
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              PanelSeparator { foreground: root.contentForeground }

              Toggle {
                width: parent.width
                label: root.t("settings.showAmount")
                description: root.t("settings.showAmountNote")
                checked: root.host ? root.host.showAmount : true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.persist({ showAmount: !(root.host && root.host.showAmount) })
              }

              Toggle {
                width: parent.width
                label: root.t("settings.notify")
                description: root.t("settings.notifyNote")
                checked: root.host ? root.host.notify : true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.persist({ notify: !(root.host && root.host.notify) })
              }

              PanelSeparator { foreground: root.contentForeground }

              // ---- Language. "System" is the default and follows the
              //      session locale; the codes next to it are an override
              //      for anyone whose desktop and coffee habit disagree.
              //      The row builds itself from the locale files that are
              //      actually shipped, so a new translation appears here
              //      without touching this panel.
              Column {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  text: root.t("settings.language")
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                ButtonGroup {
                  width: parent.width
                  focusable: false
                  value: root.host ? root.host.language : "auto"
                  foreground: root.contentForeground
                  background: root.bar ? root.bar.background : Color.background
                  fontFamily: root.contentFontFamily
                  options: {
                    var out = [{ value: "auto", label: root.t("settings.languageAuto") }]
                    var codes = root.host ? root.host.i18n.available : []
                    for (var i = 0; i < codes.length; i++)
                      out.push({ value: codes[i], label: String(codes[i]).toUpperCase() })
                    return out
                  }
                  onChanged: function(v) { root.persist({ language: v }) }
                }
              }
            }
          }

          // ---- Appearance and alerts. A row of its own: the three columns
          //      above already carry the brew model, so quiet hours and the
          //      two chart colours sit side by side rather than squeezing a
          //      colour swatch in between two number fields.
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.settingsOpen

            PanelSectionHeader {
              text: root.t("section.appearance")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Row {
              id: appearanceBody
              width: parent.width
              spacing: Style.space(20)

              readonly property real colWidth: (width - spacing * 2) / 3

              Column {
                width: appearanceBody.colWidth
                spacing: Style.space(8)

                Toggle {
                  width: parent.width
                  label: root.t("settings.nightMode")
                  description: root.t("settings.nightModeNote")
                  checked: root.host ? root.host.nightModeEnabled : true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.persist({ nightMode: !(root.host && root.host.nightModeEnabled) })
                }

                SettingField {
                  id: nightStartField
                  label: root.t("settings.nightStart")
                  from: 0
                  to: 23
                  value: root.host ? root.host.nightStartHour : 20
                  fieldWidth: appearanceBody.colWidth
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onModified: function(v) { root.persistNumber("nightStartHour", v) }
                }
              }

              // The swatch that reads "Theme" is not a colour: it is the
              // accent the chart falls back to, shown so the choice of
              // going back to it is an informed one.
              ColorField {
                width: appearanceBody.colWidth
                label: root.t("settings.curveColor")
                themeLabel: root.t("settings.colorTheme")
                value: root.host ? root.host.chartCurveColor : ""
                defaultColor: root.themeCurveColor
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) { root.persist({ chartCurveColor: v }) }
              }

              ColorField {
                width: appearanceBody.colWidth
                label: root.t("settings.thresholdColor")
                themeLabel: root.t("settings.colorTheme")
                value: root.host ? root.host.chartThresholdColor : ""
                defaultColor: root.themeThresholdColor
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) { root.persist({ chartThresholdColor: v }) }
              }
            }
          }
        }
      }
    }
  }
}
