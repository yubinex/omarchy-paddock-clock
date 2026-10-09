import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// A checkered-flag icon in the bar that opens a clock showing the wall-clock
// time at the circuit hosting the current or next F1 race. This widget owns
// fetching; Panel.qml only presents.
BarWidget {
  id: root
  moduleName: "yubinex.paddock-clock"

  // Jolpica provides coordinates but no timezone. Known circuits map directly;
  // anything new falls back to an Open-Meteo lookup from the coordinates.
  readonly property var circuitZones: ({
    albert_park: "Australia/Melbourne",
    shanghai: "Asia/Shanghai",
    suzuka: "Asia/Tokyo",
    bahrain: "Asia/Bahrain",
    jeddah: "Asia/Riyadh",
    miami: "America/New_York",
    villeneuve: "America/Toronto",
    monaco: "Europe/Monaco",
    catalunya: "Europe/Madrid",
    madring: "Europe/Madrid",
    red_bull_ring: "Europe/Vienna",
    silverstone: "Europe/London",
    spa: "Europe/Brussels",
    hungaroring: "Europe/Budapest",
    zandvoort: "Europe/Amsterdam",
    monza: "Europe/Rome",
    imola: "Europe/Rome",
    baku: "Asia/Baku",
    sepang: "Asia/Kuala_Lumpur",
    marina_bay: "Asia/Singapore",
    americas: "America/Chicago",
    rodriguez: "America/Mexico_City",
    interlagos: "America/Sao_Paulo",
    vegas: "America/Los_Angeles",
    losail: "Asia/Qatar",
    yas_marina: "Asia/Dubai"
  })

  property var races: []
  property double nowMs: Date.now()
  property var fetchedZones: ({})
  // QML's Date has no timezone support, so the system `date` and tzdata
  // supply UTC offsets (DST-correct) and the panel does the arithmetic.
  property bool offsetsReady: false
  property int trackOffsetMinutes: 0
  property int raceOffsetMinutes: 0
  property string trackZoneName: ""

  readonly property var race: {
    // Keep a race "current" until three hours after lights out.
    for (var i = 0; i < races.length; ++i)
      if (races[i].startMs + 3 * 3600000 >= nowMs) return races[i]
    return null
  }
  readonly property string zone: race ? (circuitZones[race.circuitId] || fetchedZones[race.circuitId] || "") : ""
  readonly property bool live: race !== null && nowMs >= race.startMs
  readonly property string tooltip: {
    if (!race) return races.length ? "No upcoming F1 race this season" : "Loading F1 calendar…"
    if (!offsetsReady) return race.locality
    var track = new Date(nowMs + trackOffsetMinutes * 60000)
    return race.locality + " · " + Qt.formatTime(utcAsLocal(track), "HH:mm")
  }

  // Reinterpret a Date's UTC fields as local fields so Qt.format* prints them.
  function utcAsLocal(date) {
    return new Date(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(),
      date.getUTCHours(), date.getUTCMinutes(), date.getUTCSeconds())
  }

  function parseOffset(value) {
    var match = /^([+-])(\d{2})(\d{2})$/.exec(value || "")
    if (!match) return null
    return (match[1] === "-" ? -1 : 1) * (Number(match[2]) * 60 + Number(match[3]))
  }

  function parseRaces(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (error) {
      return []
    }
    var list = data && data.MRData && data.MRData.RaceTable ? data.MRData.RaceTable.Races : null
    if (!list) return []
    var parsed = []
    for (var i = 0; i < list.length; ++i) {
      var r = list[i]
      if (!r.date || !r.Circuit || !r.Circuit.Location) continue
      var startMs = Date.parse(r.date + "T" + (r.time || "12:00:00Z"))
      if (isNaN(startMs)) continue
      parsed.push({
        season: r.season,
        round: r.round,
        name: r.raceName,
        circuit: r.Circuit.circuitName,
        circuitId: r.Circuit.circuitId,
        locality: r.Circuit.Location.locality,
        country: r.Circuit.Location.country,
        lat: r.Circuit.Location.lat,
        lon: r.Circuit.Location.long,
        startMs: startMs
      })
    }
    parsed.sort(function(a, b) { return a.startMs - b.startMs })
    return parsed
  }

  function refreshOffsets() {
    if (!zone || !race || offsetFetch.running) return
    offsetFetch.command = ["sh", "-c",
      'TZ="$1" date "+%z|%Z"; TZ="$1" date -d "@$2" "+%z"',
      "sh", zone, String(Math.floor(race.startMs / 1000))]
    offsetFetch.running = true
  }

  function lookupZone() {
    if (!race || zone || zoneFetch.running) return
    zoneFetch.circuitId = race.circuitId
    zoneFetch.command = ["curl", "-fsSL", "--proto", "=https", "--connect-timeout", "8", "--max-time", "15",
      "--max-filesize", "65536",
      "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(race.lat)
        + "&longitude=" + encodeURIComponent(race.lon) + "&timezone=auto&forecast_days=1"]
    zoneFetch.running = true
  }

  function refresh() {
    if (!calendarFetch.running) calendarFetch.running = true
  }

  // Shape contract for shell.summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  onRaceChanged: {
    offsetsReady = false
    lookupZone()
    refreshOffsets()
  }
  onZoneChanged: refreshOffsets()
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  Timer {
    // Tick on the minute boundary; offsets are re-read so DST changes apply.
    interval: 60000 - (Date.now() % 60000) + 50
    running: true
    repeat: true
    onTriggered: {
      interval = 60000 - (Date.now() % 60000) + 50
      root.nowMs = Date.now()
      root.refreshOffsets()
    }
  }

  Timer {
    interval: 3600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: calendarFetch
    command: ["curl", "-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-redirs", "3",
      "--connect-timeout", "8", "--max-time", "15", "--max-filesize", "1048576",
      "https://api.jolpi.ca/ergast/f1/current/races.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var parsed = root.parseRaces(text)
        if (parsed.length) root.races = parsed
      }
    }
  }

  Process {
    id: zoneFetch
    property string circuitId: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var data
        try {
          data = JSON.parse(text)
        } catch (error) {
          return
        }
        // Only accept a plain IANA name; it is later passed to `date` via TZ.
        if (!data || !/^[A-Za-z_]+(\/[A-Za-z0-9_+-]+)*$/.test(data.timezone || "")) return
        var next = Object.assign({}, root.fetchedZones)
        next[zoneFetch.circuitId] = data.timezone
        root.fetchedZones = next
      }
    }
  }

  Process {
    id: offsetFetch
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var lines = text.trim().split("\n")
        var now = (lines[0] || "").split("|")
        var trackOffset = root.parseOffset(now[0])
        if (trackOffset === null) return
        var raceOffset = root.parseOffset(lines[1])
        root.trackOffsetMinutes = trackOffset
        root.raceOffsetMinutes = raceOffset === null ? trackOffset : raceOffset
        // Zones without an abbreviation report a numeric one like "+08".
        root.trackZoneName = /^[+-]\d+$/.test(now[1] || "") ? "" : (now[1] || "")
        root.offsetsReady = true
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-flag_checkered
    text: ""
    active: root.live
    tooltipText: root.opened ? "" : root.tooltip
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton && root.bar)
        root.bar.run("xdg-open https://www.formula1.com/en/racing/" + (root.race ? root.race.season : ""))
      else root.togglePanel()
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Paddock Clock"
    Accessible.description: root.tooltip
  }
}
