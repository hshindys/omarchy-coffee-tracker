import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Caffeine tracker.
//
// The bar label is today's caffeine total from every source; the panel
// behind it owns the one-tap cup buttons, the brew-method switch, the tea
// and energy rosters, and the log.
//
// Caffeine is not a lookup table — it is derived from how the drink is
// actually made, and each source gets the model that fits it:
//
//   Siebträger  shots × dose × bean mg/g × extraction
//   Chemex      ml/100 × brew ratio × bean mg/g × extraction
//   French      ml/100 × brew ratio × bean mg/g × extraction
//   Türkisch    ml/100 × brew ratio × bean mg/g × extraction
//   HOLY        servings × mg per serving      (powder, you dose it)
//   Dosen       ml/100 × mg per 100 ml         (canned, it is printed on)
//   Tee         ml/100 × mg per 100 ml         (steeped, it is the leaf)
//
// Move the grind numbers and the whole coffee roster moves with them; move
// the serving strength and every HOLY portion follows. The cans and the
// teas are the fixed tables, because their caffeine is a label fact or a
// fact about the leaf rather than a choice.
//
// Everything lands in the same day total. That is the point of tracking
// three sources at once: 200 mg is 200 mg whether it came out of a
// portafilter, a teapot or a shaker.
//
// The log lives in its own state file rather than in shell.json. It is user
// data that grows, and every bar instance watches the same file, so a drink
// logged on one monitor lands on the others too.
BarWidget {
  id: root
  moduleName: "io.github.philippbellia.coffee-tracker"

  readonly property string barIcon: "󱂟"

  // ---- Brew model. Everything the coffee roster is priced from. --------
  // Every value the method switch can land on. Anything else that ends up
  // in shell.json — a typo, an older config — falls back to the portafilter.
  readonly property var methodOptions: ["portafilter", "chemex", "french", "turkish"]
  readonly property string method: {
    var m = String(setting("method", "portafilter"))
    return methodOptions.indexOf(m) >= 0 ? m : "portafilter"
  }
  // Espresso is the only method priced by the basket; every other method
  // is a per-volume brew and reads the shared ratio / yield knobs.
  readonly property bool espressoMethod: method === "portafilter"
  readonly property real beanMgPerGram: clampNum(setting("beanMgPerGram", 12), 6, 20)
  readonly property int doseGrams: Math.round(clampNum(setting("doseGrams", 18), 5, 40))
  readonly property real espressoYield: clampNum(setting("espressoYield", 65), 20, 100) / 100
  readonly property real filterRatioPer100: clampNum(setting("filterRatioPer100", 6), 3, 12)
  readonly property real filterYield: clampNum(setting("filterYield", 90), 20, 100) / 100

  // ---- HOLY. One knob, because the tub comes with a scoop and the rest of
  //      the roster is just how many scoops went in. The default is what the
  //      classic energy powder states per serving; correct it here if the
  //      line or the recipe says otherwise.
  readonly property int holyMgPerServing: Math.round(clampNum(setting("holyMgPerServing", 200), 10, 500))
  readonly property int holyMlPerServing: Math.round(clampNum(setting("holyMlPerServing", 500), 100, 1000))

  // EFSA puts the safe habitual intake for a healthy adult at 400 mg a day,
  // which is what the bar fills toward unless the user says otherwise.
  readonly property int dailyLimit: Math.round(clampNum(setting("dailyLimit", 400), 50, 2000))
  readonly property real halfLifeHours: clampNum(setting("halfLifeHours", 5), 1, 12)
  readonly property int sleepThreshold: Math.round(clampNum(setting("sleepThreshold", 50), 5, 400))

  readonly property bool notify: setting("notify", true) === true
  readonly property bool showAmount: setting("showAmount", true) !== false

  // ---- Night mode. Past the configured hour the widget goes quiet: the
  //      80 % heads-up is dropped and the daily limit is the only thing
  //      that still reaches the notification daemon. The hour reads from
  //      shell.json like every other knob here, so the quiet hours are the
  //      user's rather than the plugin's.
  readonly property bool nightModeEnabled: setting("nightMode", true) !== false
  readonly property int nightStartHour: Math.round(clampNum(setting("nightStartHour", 20), 0, 23))
  readonly property int hourOfDay: new Date(now).getHours()
  readonly property bool nightMode: nightModeEnabled && hourOfDay >= nightStartHour

  // ---- Chart colours. Empty means "follow the theme", which is what the
  //      panel draws when nothing has been chosen yet.
  readonly property string chartCurveColor: String(setting("chartCurveColor", "") || "").trim()
  readonly property string chartThresholdColor: String(setting("chartThresholdColor", "") || "").trim()

  // ---- The session's light or dark mode. The shell reads it straight out
  //      of the active theme but never publishes it, and the level palette
  //      below needs it: the same three hues that read as text on a dark
  //      bar are unreadable on a light one. colors.toml states it as
  //      `mode = "dark"` / `mode = "light"`; anything the theme does not
  //      say is taken as dark, which is what Omarchy itself defaults to.
  readonly property string themeColorsPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/current/theme/colors.toml"

  property bool systemDarkMode: true

  function loadThemeMode(raw) {
    var match = String(raw || "").match(/^\s*mode\s*=\s*["']?([A-Za-z]+)/m)
    root.systemDarkMode = match ? String(match[1]).toLowerCase() !== "light" : true
  }

  // ---- Language. "auto" follows the session locale; the panel's picker
  //      writes a concrete code here when the user overrides it. Every
  //      user-facing string in this file and in the panel goes through t().
  readonly property string language: String(setting("language", "auto") || "auto")
  readonly property I18n i18n: I18n { language: root.language }
  function t(key) {
    return root.i18n.t.apply(root.i18n, arguments)
  }
  function formatTime(ms) {
    return root.i18n.time(ms)
  }

  readonly property string logPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/coffee-log.json"

  // Entries older than this are dropped on load — the week strip only ever
  // looks back seven days, and a tracker should not quietly become an
  // archive of every cup ever pulled.
  readonly property int retentionDays: 14

  property var entries: []

  // Wall clock, ticked once a minute. Everything time-dependent — today's
  // window, the decay curve, the clear-by estimate — reads this so it moves
  // on its own and rolls over midnight without a scheduled reset.
  property real now: Date.now()

  function clampNum(value, lo, hi) {
    var n = Number(value)
    if (!isFinite(n)) return lo
    return Math.max(lo, Math.min(hi, n))
  }

  function startOfDay(ms) {
    var d = new Date(ms)
    d.setHours(0, 0, 0, 0)
    return d.getTime()
  }

  // ---- Rosters. The shape of an entry is what picks its formula:
  //      `shots` → portafilter, `servings` → HOLY powder,
  //      `mgPer100` → canned, plain `ml` → filter brew.
  readonly property var portafilterDrinks: [
    { id: "espresso",   name: t("drink.espresso"),       ml: 40,  shots: 1, icon: "󰛊", source: "coffee" },
    { id: "doppio",     name: t("drink.doppio"),         ml: 80,  shots: 2, icon: "󰅶", source: "coffee" },
    { id: "americano",  name: t("drink.americano"), ml: 200, shots: 1, icon: "󰆪", source: "coffee" },
    { id: "cortado",    name: t("drink.cortado"),        ml: 120, shots: 1, icon: "󱌏", source: "coffee" },
    { id: "cappuccino", name: t("drink.cappuccino"),     ml: 250, shots: 1, icon: "󰅷", source: "coffee" },
    { id: "latte",      name: t("drink.latte"),   ml: 250, shots: 1, icon: "󰊦", source: "coffee" },
    { id: "flatwhite",  name: t("drink.flatwhite"),     ml: 200, shots: 2, icon: "󱌎", source: "coffee" }
  ]

  readonly property var chemexDrinks: [
    { id: "filter200",  name: t("drink.filter200"), ml: 200, icon: "󰆪", source: "coffee" },
    { id: "filter300",  name: t("drink.filter300"),    ml: 300, icon: "󰅶", source: "coffee" },
    { id: "filter500",  name: t("drink.filter500"),  ml: 500, icon: "󰙚", source: "coffee" }
  ]

  // French press: the same full-immersion numbers as the filter brew, only
  // the cup sizes are its own — a beaker pours a mug, not a 200 ml cup.
  readonly property var frenchDrinks: [
    { id: "french250",  name: t("drink.french250"),  ml: 250, icon: "󰆪", source: "coffee" },
    { id: "french350",  name: t("drink.french350"),  ml: 350, icon: "󰅶", source: "coffee" },
    { id: "french500",  name: t("drink.french500"),  ml: 500, icon: "󰙚", source: "coffee" }
  ]

  // Turkish: the fincan is small and the second pour is a second cup, so
  // the roster is volumes rather than named drinks.
  readonly property var turkishDrinks: [
    { id: "turkish60",  name: t("drink.turkish60"),   ml: 60,  icon: "󰛊", source: "coffee" },
    { id: "turkish120", name: t("drink.turkish120"),  ml: 120, icon: "󰅷", source: "coffee" },
    { id: "turkish333", name: t("drink.turkish333"),  ml: 333, icon: "󰅶", source: "coffee" }
  ]

  // Kept so old log entries still resolve; the tab no longer offers HOLY.
  readonly property var holyDrinks: [
    { id: "holy-half",  name: t("drink.holy-half"),    servings: 0.5, icon: "󱐩", source: "energy" },
    { id: "holy-1",     name: t("drink.holy-1"),    servings: 1.0, icon: "󱄎", source: "energy" },
    { id: "holy-1-5",   name: t("drink.holy-1-5"), servings: 1.5, icon: "󰳪", source: "energy" },
    { id: "holy-2",     name: t("drink.holy-2"),  servings: 2.0, icon: "󰠠", source: "energy" }
  ]

  // Cold drinks are the one fixed table here: their caffeine is printed on
  // the label, not chosen by you. Red Bull sits at the 32 mg/100 ml EU
  // ceiling, Pepsi and ice tea at 10; juice, malt, herbs and others are
  // caffeine-free and log volume only.
  readonly property var canDrinks: [
    { id: "juice",   name: t("drink.juice"),   ml: 400, mgPer100: 0, icon: "\uf01ab", source: "energy" },
    { id: "pepsi",   name: t("drink.pepsi"),   ml: 333, mgPer100: 10, icon: "\uf1070", source: "energy" },
    { id: "malt",    name: t("drink.malt"),    ml: 333, mgPer100: 0, icon: "\uf1071", source: "energy" },
    { id: "herbs",   name: t("drink.herbs"),   ml: 333, mgPer100: 0, icon: "\uf0e66", source: "energy" },
    { id: "others",  name: t("drink.others"),  ml: 333, mgPer100: 0, icon: "\uf02a6", source: "energy" },
    { id: "redbull", name: t("drink.redbull"), ml: 333, mgPer100: 32, icon: "\uf140b", source: "energy" },
    { id: "icetea",  name: t("drink.icetea"),  ml: 250, mgPer100: 10, icon: "\uf0d9e", source: "energy" }
  ]

  readonly property var teaDrinks: [
    { id: "blacktea",       name: t("drink.blacktea"),       ml: 333, mgPer100: 20, icon: "\uf0d9e", source: "tea" },
    { id: "blacktea-small", name: t("drink.blacktea-small"), ml: 150, mgPer100: 20, icon: "\uf0d9e", source: "tea" },
    { id: "earlgrey",       name: t("drink.earlgrey"),       ml: 333, mgPer100: 20, icon: "\uf1319", source: "tea" },
    { id: "greentea",       name: t("drink.greentea"),       ml: 333, mgPer100: 12, icon: "\uf032a", source: "tea" },
    { id: "greentea-small", name: t("drink.greentea-small"), ml: 150, mgPer100: 12, icon: "\uf032a", source: "tea" },
    { id: "milktea",        name: t("drink.milktea"),        ml: 333, mgPer100: 20, icon: "\uf02a6", source: "tea" },
    { id: "karak",          name: t("drink.karak"),          ml: 333, mgPer100: 30, icon: "\uf0d9f", source: "tea" },
    { id: "masala",         name: t("drink.masala"),         ml: 333, mgPer100: 20, icon: "\uf130f", source: "tea" },
    { id: "adeni",          name: t("drink.adeni"),          ml: 333, mgPer100: 20, icon: "\uf02a6", source: "tea" },
    { id: "matcha",         name: t("drink.matcha"),         ml: 333, mgPer100: 50, icon: "\uf01aa", source: "tea" }
  ]

  readonly property var drinks: {
    if (method === "chemex") return chemexDrinks
    if (method === "french") return frenchDrinks
    if (method === "turkish") return turkishDrinks
    return portafilterDrinks
  }
  readonly property string methodLabel: t("method." + method)
  readonly property string methodIcon: {
    if (method === "chemex") return "󱜼"
    if (method === "french") return "󰙚"
    if (method === "turkish") return "󰛊"
    return "󱂟"
  }

  // The one-tap default behind the middle click: the shot on the portafilter,
  // the standard cup on every other brew.
  readonly property var defaultDrink: drinks.length > 0 ? drinks[0] : null

  function drinkById(id) {
    var pools = [portafilterDrinks, chemexDrinks, frenchDrinks, turkishDrinks, holyDrinks, canDrinks, teaDrinks]
    for (var p = 0; p < pools.length; p++)
      for (var i = 0; i < pools[p].length; i++)
        if (pools[p][i].id === id) return pools[p][i]
    return null
  }

  // The log stores the name as it read when the drink was logged, so a
  // language change would otherwise leave yesterday's cups in yesterday's
  // language. Re-resolve through the roster and keep the stored name only
  // for entries whose id no longer exists.
  function entryName(entry) {
    if (!entry) return ""
    var drink = drinkById(entry.id)
    return drink ? drink.name : String(entry.name || t("drink.fallback"))
  }

  // Grams of coffee a brewed drink puts through the water. The espresso path
  // counts baskets, the filter path counts brew ratio against volume.
  function gramsFor(drink) {
    if (!drink) return 0
    if (drink.shots !== undefined) return Number(drink.shots) * doseGrams
    return (Number(drink.ml) / 100) * filterRatioPer100
  }

  function caffeineFor(drink) {
    if (!drink) return 0
    if (drink.servings !== undefined) return Math.round(Number(drink.servings) * holyMgPerServing)
    if (drink.mgPer100 !== undefined) return Math.round((Number(drink.ml) / 100) * Number(drink.mgPer100))
    var extraction = drink.shots !== undefined ? espressoYield : filterYield
    return Math.round(gramsFor(drink) * beanMgPerGram * extraction)
  }

  // HOLY is dosed in scoops, so its volume follows the serving size rather
  // than sitting in the roster as a fixed number.
  function volumeFor(drink) {
    if (!drink) return 0
    if (drink.servings !== undefined) return Math.round(Number(drink.servings) * holyMlPerServing)
    return Number(drink.ml) || 0
  }

  // The source an entry is booked under: one log, three sources, and only
  // energy kept apart from the cups — a can is counted in cans, while a
  // steeped cup is a cup like any other.
  function sourceOf(drink) {
    if (!drink) return "coffee"
    if (drink.source === "energy") return "energy"
    if (drink.source === "tea") return "tea"
    return "coffee"
  }

  readonly property int mgPerShot: Math.round(doseGrams * beanMgPerGram * espressoYield)
  readonly property int mgPerFilterCup: Math.round(2 * filterRatioPer100 * beanMgPerGram * filterYield)

  // ---- Today ----------------------------------------------------------
  readonly property var todayEntries: {
    var from = startOfDay(now)
    var out = []
    for (var i = 0; i < entries.length; i++) if (entries[i].t >= from) out.push(entries[i])
    return out
  }

  readonly property int todayMg: {
    var total = 0
    for (var i = 0; i < todayEntries.length; i++) total += Number(todayEntries[i].mg) || 0
    return Math.round(total)
  }

  readonly property int todayEnergyMg: {
    var total = 0
    for (var i = 0; i < todayEntries.length; i++)
      if (todayEntries[i].source === "energy") total += Number(todayEntries[i].mg) || 0
    return Math.round(total)
  }

  readonly property int todayCoffeeMg: todayMg - todayEnergyMg - todayTeaMg

  readonly property int todayTeaMg: {
    var total = 0
    for (var i = 0; i < todayEntries.length; i++)
      if (todayEntries[i].source === "tea") total += Number(todayEntries[i].mg) || 0
    return Math.round(total)
  }

  // The day, named bucket by bucket — but only when there is more than one
  // source in it. A single source is already named by the summary above it,
  // and a tea day must never be reported as a coffee day.
  function bucketSummary() {
    var parts = []
    if (todayCoffeeMg > 0) parts.push(t("bucket.coffee", todayCoffeeMg))
    if (todayTeaMg > 0) parts.push(t("bucket.tea", todayTeaMg))
    if (todayEnergyMg > 0) parts.push(t("bucket.energy", todayEnergyMg))
    return parts.length > 1 ? parts.join(" · ") : ""
  }

  readonly property int todayMl: {
    var total = 0
    for (var i = 0; i < todayEntries.length; i++) total += Number(todayEntries[i].ml) || 0
    return Math.round(total)
  }

  readonly property int todayCups: {
    var n = 0
    for (var i = 0; i < todayEntries.length; i++) if (todayEntries[i].source !== "energy") n += 1
    return n
  }

  readonly property int todayCans: todayEntries.length - todayCups

  readonly property real todayProgress: dailyLimit > 0 ? Math.max(0, Math.min(1, todayMg / dailyLimit)) : 0
  readonly property bool overLimit: todayMg > dailyLimit
  readonly property int remainingMg: Math.max(0, dailyLimit - todayMg)

  // How many more of the default cup fit under the limit — the question
  // actually being asked when someone glances at the bar mid-afternoon.
  readonly property int remainingCups: {
    var per = caffeineFor(defaultDrink)
    return per > 0 ? Math.floor(remainingMg / per) : 0
  }

  // ---- Level colour. Green under half the ceiling, yellow to 80 %, red
  //      past it — the three states the bar label, the panel fill and the
  //      percentage pill all speak in.
  //
  //      The two thresholds are not hard steps: they meet over a narrow
  //      window either side of 50 % and 80 %, so the colour the panel
  //      animates toward is already close to the one it lands on and a
  //      single sip never snaps green to yellow in one frame. Exactly on
  //      the threshold the colour is exactly the colour the rule names.
  //
  //      Two palettes, picked by the session's own light or dark mode: a
  //      dark bar wants the bright trio, a light one the deep trio, and
  //      the theme is the only thing here that knows which it is.
  readonly property color levelGreen: systemDarkMode ? "#7ee787" : "#1a7f37"
  readonly property color levelYellow: systemDarkMode ? "#e3b341" : "#9a6700"
  readonly property color levelRed: systemDarkMode ? "#ff7b72" : "#cf222e"

  function mixLevel(from, to, amount) {
    var k = Math.max(0, Math.min(1, amount))
    return Qt.rgba(from.r + (to.r - from.r) * k,
      from.g + (to.g - from.g) * k,
      from.b + (to.b - from.b) * k)
  }

  function levelColorFor(progress) {
    var p = Math.max(0, Math.min(1, Number(progress) || 0))
    if (p <= 0.45) return levelGreen
    if (p < 0.55) return mixLevel(levelGreen, levelYellow, (p - 0.45) / 0.10)
    if (p <= 0.75) return levelYellow
    if (p < 0.85) return mixLevel(levelYellow, levelRed, (p - 0.75) / 0.10)
    return levelRed
  }

  readonly property color levelColor: levelColorFor(todayProgress)

  // ---- Decay. First-order elimination at the configured half-life; the
  //      standard 5 h is the population mean for a healthy adult. Source
  //      makes no difference here — the molecule is the same one.
  function activeCaffeineAt(atMs) {
    var total = 0
    for (var i = 0; i < entries.length; i++) {
      var dt = (atMs - entries[i].t) / 3600000
      if (dt < 0) continue
      total += Number(entries[i].mg) * Math.pow(0.5, dt / halfLifeHours)
    }
    return total
  }

  readonly property int activeMg: Math.round(activeCaffeineAt(now))
  readonly property real activeProgress: dailyLimit > 0 ? Math.max(0, Math.min(1, activeMg / dailyLimit)) : 0

  // When the residue drops under the sleep threshold. Stepped rather than
  // solved: several doses with different ages have no closed form, and a
  // five-minute grid is finer than the estimate deserves.
  readonly property real clearAtMs: {
    if (activeCaffeineAt(now) <= sleepThreshold) return now
    var step = 300000
    for (var t = now + step; t <= now + 24 * 3600000; t += step)
      if (activeCaffeineAt(t) <= sleepThreshold) return t
    return -1
  }

  // ---- Decay curve. The same activeCaffeineAt the read-outs use, sampled
  //      across a window rather than at a single instant, so the panel can
  //      draw the shape of the day instead of one number from it.
  //
  //      The window starts at midnight, because that is the day the rest of
  //      the panel talks about, and ends a little past the moment the
  //      residue drops under the threshold — that crossing is the question
  //      the curve exists to answer, so it must be inside the frame. With
  //      nothing left to wait for it still runs an hour ahead, and it never
  //      looks more than a day forward.
  readonly property real curveStartMs: startOfDay(now)

  readonly property real curveEndMs: {
    var end = clearAtMs >= 0 ? clearAtMs + 1800000 : now + 24 * 3600000
    end = Math.max(end, now + 3600000)
    return Math.min(end, now + 24 * 3600000)
  }

  // An even grid would round off the steps where a drink lands, so every
  // entry in the window also contributes the two samples that bracket it:
  // the curve keeps its vertical jumps instead of leaning into them.
  readonly property var decayCurve: {
    var from = curveStartMs
    var to = curveEndMs
    if (!(to > from)) return []

    var times = []
    var steps = 96
    for (var i = 0; i <= steps; i++) times.push(from + (to - from) * i / steps)

    for (var j = 0; j < entries.length; j++) {
      var at = entries[j].t
      if (at > from && at < to) {
        times.push(at - 1)
        times.push(at)
      }
    }
    times.sort(function(a, b) { return a - b })

    var out = []
    for (var k = 0; k < times.length; k++)
      out.push({ t: times[k], mg: activeCaffeineAt(times[k]) })
    return out
  }

  // Headroom so the threshold line never sits on the ceiling of the plot,
  // which is what it would do on a day that stayed close to it.
  readonly property real curvePeak: {
    var peak = sleepThreshold * 1.4
    for (var i = 0; i < decayCurve.length; i++) peak = Math.max(peak, decayCurve[i].mg)
    return peak
  }

  readonly property string clearAtLabel: {
    if (todayEntries.length === 0 && activeMg <= 0) return t("unit.none")
    if (clearAtMs < 0) return t("unit.over24h")
    if (clearAtMs <= now + 60000) return t("unit.now")
    return formatTime(clearAtMs)
  }

  // ---- Week strip. Split by source so the columns show where the day's
  //      caffeine came from, not just how much of it there was.
  readonly property var weekTotals: {
    var out = []
    for (var d = 6; d >= 0; d--) {
      var day = new Date(now)
      day.setDate(day.getDate() - d)
      var from = startOfDay(day.getTime())
      var next = new Date(from)
      next.setDate(next.getDate() + 1)
      var to = startOfDay(next.getTime())
      var coffeeMg = 0
      var teaMg = 0
      var energyMg = 0
      var count = 0
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].t >= from && entries[i].t < to) {
          if (entries[i].source === "energy") energyMg += Number(entries[i].mg) || 0
          else if (entries[i].source === "tea") teaMg += Number(entries[i].mg) || 0
          else coffeeMg += Number(entries[i].mg) || 0
          count += 1
        }
      }
      out.push({
        day: from,
        mg: Math.round(coffeeMg + teaMg + energyMg),
        coffeeMg: Math.round(coffeeMg),
        teaMg: Math.round(teaMg),
        energyMg: Math.round(energyMg),
        count: count,
        today: d === 0
      })
    }
    return out
  }

  readonly property int weekPeak: {
    var peak = dailyLimit
    for (var i = 0; i < weekTotals.length; i++) peak = Math.max(peak, weekTotals[i].mg)
    return peak
  }

  // ---- The calendar week, Monday to Sunday. The strip above is a rolling
  //      seven days and says nothing about "this week", which is the
  //      question the tooltip answers: how much has this week cost so far,
  //      what that works out to per day, and which way that daily rate is
  //      moving against the same stretch of last week.
  //
  //      The average divides by the days that have actually happened —
  //      Monday's tooltip should not read as a crash just because only one
  //      day of the week is in the books — and the trend compares like with
  //      like by measuring last week over those same days only.
  function startOfWeek(ms) {
    var day = new Date(ms)
    day.setHours(0, 0, 0, 0)
    day.setDate(day.getDate() - ((day.getDay() + 6) % 7))
    return day.getTime()
  }

  function mgBetween(fromMs, toMs) {
    var total = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].t >= fromMs && entries[i].t < toMs) total += Number(entries[i].mg) || 0
    return Math.round(total)
  }

  readonly property real weekStartMs: startOfWeek(now)

  readonly property real weekEndMs: startOfWeek(weekStartMs + 7 * 86400000)

  // Stepped day by day rather than divided by 86400000, because a week
  // containing a clock change is 167 or 169 hours long and the count is a
  // calendar question, not an elapsed-time one.
  readonly property int weekElapsedDays: {
    var count = 1
    var cursor = new Date(weekStartMs)
    var today = startOfDay(now)
    while (cursor.getTime() < today && count < 7) {
      cursor.setDate(cursor.getDate() + 1)
      count += 1
    }
    return count
  }

  readonly property int weekMg: mgBetween(weekStartMs, weekEndMs)
  readonly property int weekDayAverage: weekElapsedDays > 0 ? Math.round(weekMg / weekElapsedDays) : 0

  readonly property int previousWeekMg: mgBetween(startOfWeek(weekStartMs - 7 * 86400000), weekStartMs)
  readonly property int previousWeekDayAverage: weekElapsedDays > 0 ? Math.round(previousWeekMg / weekElapsedDays) : 0

  // 1 up, -1 down, 0 flat. A swing smaller than a tenth of a cup or five
  // percent of last week's rate — whichever is larger — is one drink, not a
  // direction, and an arrow that flickers over a single espresso is worse
  // than no arrow at all.
  readonly property int weekTrend: {
    var noise = Math.max(10, previousWeekDayAverage * 0.05)
    if (weekDayAverage - previousWeekDayAverage > noise) return 1
    if (previousWeekDayAverage - weekDayAverage > noise) return -1
    return 0
  }

  readonly property string weekTrendArrow: weekTrend > 0 ? "↑" : (weekTrend < 0 ? "↓" : "→")

  // ---- Persistence ----------------------------------------------------
  function loadLog(raw) {
    var parsed = []
    try {
      var json = JSON.parse(raw || "{}")
      if (json && Array.isArray(json.entries)) parsed = json.entries
    } catch (e) {
      parsed = []
    }

    var cutoff = Date.now() - retentionDays * 86400000
    var cleaned = []
    for (var i = 0; i < parsed.length; i++) {
      var e = parsed[i]
      var t = Number(e && e.t)
      var mg = Number(e && e.mg)
      if (!isFinite(t) || !isFinite(mg) || t < cutoff) continue
      cleaned.push({
        t: t,
        id: String((e && e.id) || ""),
        name: String((e && e.name) || root.t("drink.fallback")),
        ml: Number(e && e.ml) || 0,
        mg: Math.round(mg),
        method: String((e && e.method) || ""),
        // Entries written before the energy roster existed carry no source;
        // they were all coffee, so that is what they become. Anything else
        // is kept as it was written.
        source: (e && (e.source === "energy" || e.source === "tea")) ? String(e.source) : "coffee"
      })
    }
    cleaned.sort(function(a, b) { return a.t - b.t })
    root.entries = cleaned
  }

  function saveLog() {
    logFile.setText(JSON.stringify({ version: 1, entries: root.entries }, null, 2) + "\n")
  }

  // Writes back into this widget's shell.json layout entry. Applied locally
  // first so the UI moves on the click itself; the write comes back through
  // the bar as the same value.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) {
      // A NaN out of a half-built control would round-trip through JSON as
      // null, come back as the clamp floor, and silently rewrite the brew
      // model. Drop it instead and keep whatever the setting already was.
      var value = values[key]
      if (typeof value === "number" && !isFinite(value)) continue
      entry[key] = value
    }

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // `kind` is what decides whether night mode lets the message through:
  // "limit" is the one that survives the quiet hours, everything else is
  // the daytime chatter that stops at the configured hour.
  function notifySend(title, body, kind) {
    if (!notify) return
    if (nightMode && String(kind || "") !== "limit") return
    Quickshell.execDetached(["notify-send", "-a", t("notify.appName"), title, body])
  }

  // ---- The cup, animated. Bumped once per logged drink and held for two
  //      seconds; the bar and the panel each watch this counter, run their
  //      own bounce and, in the panel's case, lift a little steam, then
  //      settle back to idle with nothing left moving.
  property int cupPulse: 0
  property bool cupAnimating: false

  function pulseCup() {
    root.cupPulse += 1
    root.cupAnimating = true
    cupAnimTimer.restart()
  }

  Timer {
    id: cupAnimTimer
    interval: 2000
    onTriggered: root.cupAnimating = false
  }

  // ---- Actions --------------------------------------------------------
  function addDrink(drink) {
    if (!drink) return
    var mg = caffeineFor(drink)
    var before = todayMg
    var after = before + mg

    var next = entries.slice()
    next.push({
      t: Date.now(),
      id: String(drink.id),
      name: String(drink.name),
      ml: volumeFor(drink),
      mg: mg,
      method: sourceOf(drink) === "coffee" ? root.method : sourceOf(drink),
      source: sourceOf(drink)
    })
    root.now = Date.now()
    root.entries = next
    saveLog()
    pulseCup()

    // A heads-up at the 80 % line — the same line the level colour turns
    // red on, so the alert and the bar agree about when things are getting
    // close. It is a daytime courtesy: night mode drops it, and it never
    // fires on a drink that also crosses the limit, so one sip can never
    // produce two notifications.
    var warnAt = dailyLimit * 0.8
    if (before < warnAt && after >= warnAt && after <= dailyLimit)
      notifySend(t("notify.warnTitle"), t("notify.warnBody", after, dailyLimit), "warn")

    // Only on the crossing, not on every drink past it — a limit that scolds
    // you all evening stops being information. This is the one notification
    // night mode keeps.
    if (before <= dailyLimit && after > dailyLimit)
      notifySend(t("notify.limitTitle"), t("notify.limitBody", after, dailyLimit), "limit")
  }

  function addDrinkId(id) {
    addDrink(drinkById(id))
  }

  function removeEntryAt(timestamp) {
    var next = []
    var dropped = false
    for (var i = 0; i < entries.length; i++) {
      if (!dropped && entries[i].t === timestamp) { dropped = true; continue }
      next.push(entries[i])
    }
    if (!dropped) return
    root.entries = next
    saveLog()
  }

  function undoLast() {
    if (todayEntries.length === 0) return
    removeEntryAt(todayEntries[todayEntries.length - 1].t)
  }

  function clearToday() {
    if (todayEntries.length === 0) return
    var from = startOfDay(now)
    var next = []
    for (var i = 0; i < entries.length; i++) if (entries[i].t < from) next.push(entries[i])
    root.entries = next
    saveLog()
  }

  function setMethod(value) {
    var m = String(value)
    if (methodOptions.indexOf(m) < 0) m = "portafilter"
    persistSettings({ method: m })
  }

  // The panel's `M` shortcut walks the roster in order rather than flipping
  // between two values, now that there are more than two to land on.
  function cycleMethod() {
    var i = methodOptions.indexOf(method)
    setMethod(methodOptions[(i + 1) % methodOptions.length])
  }

  function formatVolume(ml) {
    if (ml >= 1000) return i18n.decimal(Math.round(ml / 100) / 10, 1) + " " + t("unit.litre")
    return ml + " " + t("unit.millilitre")
  }

  // "2 cups · 1 energy", with whichever half is actually there.
  readonly property string sourceSummary: {
    var parts = []
    if (todayCups > 0)
      parts.push(todayCups === 1 ? t("count.cup.one") : t("count.cup.other", todayCups))
    if (todayCans > 0)
      parts.push(todayCans === 1 ? t("count.energy.one") : t("count.energy.other", todayCans))
    if (parts.length === 0) return t("count.cup.zero")
    return parts.join(" · ")
  }

  // The calendar week in one line, for the tooltip: what it has cost so
  // far, what that works out to per day, and which way that daily rate is
  // running against the same stretch of last week.
  readonly property string weekSummary: t("bar.week", weekMg, weekDayAverage, weekTrendArrow)

  // ---- Bar label ------------------------------------------------------
  readonly property string displayText: showAmount
    ? barIcon + "  " + todayMg
    : barIcon
  readonly property var verticalLines: showAmount ? [barIcon, String(todayMg)] : [barIcon]

  readonly property string tooltip: {
    var head = sourceSummary + " · " + todayMg + " / " + dailyLimit + " mg"
    var rest = "· " + (overLimit
      ? t("bar.overGoal", todayMg - dailyLimit)
      : t("bar.remaining", remainingMg))
    var summary = bucketSummary()
    var split = summary ? "\n" + summary : ""
    return head + " " + rest + split
      + "\n" + weekSummary
      + "\n" + t("bar.inBody", activeMg, sleepThreshold, clearAtLabel)
      + "\n" + t("bar.method", methodLabel)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  function openTab(name) {
    if (panelLoader.item)
      panelLoader.item.tab = (name === "energy" || name === "tea") ? name : "coffee"
    open()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // FileView cannot watch a file whose directory does not exist yet, so the
  // state dir is created before the first read.
  Process {
    id: stateDirProc
    command: ["mkdir", "-p", (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy"]
    onExited: logFile.reload()
  }

  FileView {
    id: logFile
    path: root.logPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadLog(text())
    onLoadFailed: root.loadLog("{}")
    onFileChanged: reload()
  }

  // The theme's own colours.toml, read for nothing but the `mode` line.
  // The shell reloads the theme through its own IPC rather than by
  // restarting anything, so the file is re-read with the minute tick as
  // well — a theme switch lands within sixty seconds instead of never.
  FileView {
    id: themeColorsFile
    path: root.themeColorsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeMode(text())
    onLoadFailed: root.systemDarkMode = true
    onFileChanged: reload()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: {
      root.now = Date.now()
      themeColorsFile.reload()
    }
  }

  Component.onCompleted: stateDirProc.running = true

  // The bounce, on whatever the widget is currently showing. Restarting it
  // on every log means a second cup mid-animation picks up where the first
  // left off rather than snapping back to scale 1 first.
  onCupPulseChanged: if (cupPulse > 0) cupBounce.restart()

  SequentialAnimation {
    id: cupBounce
    loops: 3
    NumberAnimation { target: button; property: "scale"; to: 1.16; duration: 190; easing.type: Easing.OutBack }
    NumberAnimation { target: button; property: "scale"; to: 1.0; duration: 430; easing.type: Easing.InOutSine }
  }

  IpcHandler {
    target: "coffee"

    function add(drink: string): void { root.addDrinkId(drink) }
    function espresso(): void { root.addDrinkId("espresso") }
    function holy(): void { root.addDrinkId("holy-1") }
    function undo(): void { root.undoLast() }
    function clear(): void { root.clearToday() }
    function method(value: string): void { root.setMethod(value) }
    function today(): string {
      var summary = root.bucketSummary()
      return root.sourceSummary + " · " + root.todayMg + " / " + root.dailyLimit + " mg"
        + (summary ? " (" + summary + ")" : "")
        + " · " + root.t("panel.inBody", root.activeMg)
    }
    function open(): void { root.open() }
    function energy(): void { root.openTab("energy") }
    function coffee(): void { root.openTab("coffee") }
    function tea(): void { root.openTab("tea") }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? true : text !== ""
    // The label speaks in the level colour as soon as there is anything to
    // measure — green under half the ceiling, yellow to 80 %, red past it —
    // which is also the one state where a caffeine counter has something to
    // say rather than something to show. WidgetButton animates the colour
    // change, so the bar eases into its new state instead of stepping.
    active: root.todayEntries.length > 0
    activeColor: root.levelColor
    dimmed: root.todayEntries.length === 0
    tooltipText: root.tooltip
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.undoLast()
      else if (b === Qt.MiddleButton) root.addDrink(root.defaultDrink)
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.85 : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
