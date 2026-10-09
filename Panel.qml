import QtQuick
import qs.Commons
import qs.Ui

// Track-time popout: an analog clock and digital readout for the circuit's
// local time, plus the race start in track and local time. All data comes
// from the bar widget; opening the panel never triggers a network request.
Panel {
  id: root
  moduleName: "yubinex.paddock-clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  // Seconds tick only while the panel is open.
  property double nowMs: Date.now()

  readonly property var race: hostWidget ? hostWidget.race : null
  readonly property bool ready: hostWidget !== null && hostWidget.offsetsReady && race !== null
  readonly property int trackOffset: hostWidget ? hostWidget.trackOffsetMinutes : 0
  readonly property int localOffset: -new Date(nowMs).getTimezoneOffset()
  readonly property var trackNow: hostWidget ? hostWidget.utcAsLocal(new Date(nowMs + trackOffset * 60000)) : new Date(nowMs)
  readonly property bool live: race !== null && nowMs >= race.startMs

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color f1Red: "#e10600"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool digitalClock: setting("digitalClock", false) === true
  readonly property string barIcon: setting("barIcon", "Flag") === "Globe" ? "Globe" : "Flag"
  readonly property bool daytime: trackNow.getHours() >= 6 && trackNow.getHours() < 18

  component Hand: Item {
    property real angle: 0
    property real length: 0.5
    property real thickness: 3
    property color handColor: "white"
    property real tail: 0
    readonly property real dialRadius: width / 2
    anchors.fill: parent
    rotation: angle
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(parent.thickness)
      height: parent.dialRadius * (parent.length + parent.tail)
      y: parent.dialRadius * (1 - parent.length)
      radius: width / 2
      color: parent.handColor
      antialiasing: true
    }
  }

  component DetailRow: Item {
    property string label: ""
    property string value: ""
    property color valueColor: Color.foreground
    property color labelColor: Color.foreground
    property string fontName: Style.font.family
    width: parent ? parent.width : 0
    height: Math.max(labelText.implicitHeight, valueText.implicitHeight)
    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: parent.labelColor
      font.family: parent.fontName
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
    Text {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - labelText.implicitWidth - Style.space(12))
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
      text: parent.value
      color: parent.valueColor
      font.family: parent.fontName
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  function offsetLabel(minutes) {
    var sign = minutes < 0 ? "−" : "+"
    var abs = Math.abs(minutes)
    return "UTC" + sign + Math.floor(abs / 60) + (abs % 60 ? ":" + twoDigits(abs % 60) : "")
  }

  function differenceLabel() {
    var diff = trackOffset - localOffset
    if (diff === 0) return "same as track"
    var abs = Math.abs(diff)
    return "track " + (diff > 0 ? "+" : "−") + Math.floor(abs / 60) + (abs % 60 ? ":" + twoDigits(abs % 60) : "") + " h"
  }

  function twoDigits(value) { return value < 10 ? "0" + value : String(value) }

  function countdown() {
    if (!race) return ""
    if (live) return "Race is live"
    var minutes = Math.ceil((race.startMs - nowMs) / 60000)
    var days = Math.floor(minutes / 1440)
    var hours = Math.floor((minutes % 1440) / 60)
    var mins = minutes % 60
    return (days ? days + "d " : "") + (days || hours ? hours + "h " : "") + mins + "m"
  }

  function raceTrackTime() {
    if (!race || !hostWidget) return ""
    var date = hostWidget.utcAsLocal(new Date(race.startMs + hostWidget.raceOffsetMinutes * 60000))
    return Qt.formatDateTime(date, "ddd d MMM · HH:mm")
  }

  // Saves to this widget's entry in shell.json, like the Omarchy settings UI.
  function persistSettings(values) {
    var entry = { id: moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    for (var key in values) entry[key] = values[key]
    settings = entry
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function toggleClockStyle() {
    persistSettings({ digitalClock: !digitalClock })
  }

  function open() {
    nowMs = Date.now()
    controller.show()
  }

  Timer {
    interval: 1000 - (Date.now() % 1000) + 10
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      interval = 1000 - (Date.now() % 1000) + 10
      root.nowMs = Date.now()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "d") root.toggleClockStyle() }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(16)

      // Header: round, Grand Prix, circuit, and the clock-style toggle.
      Item {
        width: parent.width
        height: header.implicitHeight

        PanelActionButton {
          id: styleToggle
          anchors.top: parent.top
          anchors.right: parent.right
          // nf-md-clock_outline / nf-md-clock_digital
          iconText: root.digitalClock ? "\udb80\udd50" : "\udb83\ude97"
          tooltipText: root.digitalClock ? "Show analog clock (D)" : "Show digital clock (D)"
          foreground: root.dim
          hoverColor: root.fg
          fontFamily: root.fontFamily
          size: Style.space(28)
          bordered: true
          onClicked: root.toggleClockStyle()
        }

        Column {
          id: header
          width: parent.width - styleToggle.width - Style.space(8)
          spacing: Style.space(3)

          Row {
            spacing: Style.space(8)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(4)
              height: roundLabel.height
              color: root.f1Red
            }
            Text {
              id: roundLabel
              text: root.race ? "FORMULA 1 · ROUND " + root.race.round : "FORMULA 1"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              visible: root.live
              text: "● LIVE"
              color: root.f1Red
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
          Text {
            width: parent.width
            text: root.race ? root.race.name : (root.hostWidget && root.hostWidget.races.length ? "Season complete" : "Loading calendar…")
            elide: Text.ElideRight
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 1.35
            font.bold: true
          }
          Text {
            width: parent.width
            visible: root.race !== null
            text: root.race ? root.race.circuit + " · " + root.race.country : ""
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // Analog clock face.
      Item {
        id: dial
        visible: !root.digitalClock
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, Style.space(200))
        height: width
        opacity: root.ready ? 1 : 0.35

        readonly property real radius: width / 2
        readonly property int hours: root.trackNow.getHours()
        readonly property int minutes: root.trackNow.getMinutes()
        readonly property int seconds: root.trackNow.getSeconds()

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
          border.width: Style.space(2)
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
        }

        Repeater {
          model: 60
          Item {
            required property int index
            readonly property bool major: index % 5 === 0
            anchors.fill: parent
            rotation: index * 6
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              y: Style.space(8)
              width: parent.major ? Style.space(3) : Style.space(1)
              height: parent.major ? Style.space(12) : Style.space(5)
              radius: width / 2
              color: parent.index === 0 ? root.f1Red : parent.major ? root.fg : root.dim
            }
          }
        }

        // Sun or moon in the lower half hints at day/night at the circuit.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height * 0.62
          // nf-md-weather_sunny / nf-md-weather_night
          text: root.daytime ? "\udb81\udd99" : "\udb81\udd94"
          color: root.daytime ? "#e0b84f" : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body * 1.3
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height * 0.26
          text: root.race ? root.race.locality.toUpperCase() : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.9
          font.bold: true
          font.letterSpacing: 1
        }

        Hand {
          handColor: root.fg
          angle: (dial.hours % 12) * 30 + dial.minutes * 0.5
          length: 0.5
          thickness: 5
        }
        Hand {
          handColor: root.fg
          angle: dial.minutes * 6 + dial.seconds * 0.1
          length: 0.74
          thickness: 3
        }
        Hand {
          angle: dial.seconds * 6
          length: 0.82
          tail: 0.16
          thickness: 1.5
          handColor: root.f1Red
        }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(10)
          height: width
          radius: width / 2
          color: root.f1Red
          border.width: Style.space(2)
          border.color: root.fg
        }
      }

      // Digital readout. In digital mode it replaces the dial as the hero.
      Column {
        width: parent.width
        spacing: Style.space(2)
        topPadding: root.digitalClock ? Style.space(14) : 0
        bottomPadding: root.digitalClock ? Style.space(10) : 0

        Row {
          visible: root.digitalClock
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.daytime ? "\udb81\udd99" : "\udb81\udd94"
            color: root.daytime ? "#e0b84f" : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 1.2
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.race ? root.race.locality.toUpperCase() : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }
        }

        Row {
          visible: root.digitalClock
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)
          opacity: root.ready ? 1 : 0.35
          Text {
            id: bigTime
            text: root.ready ? Qt.formatTime(root.trackNow, "HH") + "<font color=\"" + root.f1Red + "\">:</font>"
              + Qt.formatTime(root.trackNow, "mm") : "--:--"
            textFormat: Text.StyledText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 5.2
            font.bold: true
          }
          Text {
            anchors.baseline: bigTime.baseline
            text: root.ready ? Qt.formatTime(root.trackNow, "ss") : "--"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * 1.9
            font.bold: true
          }
        }

        Text {
          visible: !root.digitalClock
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.ready ? Qt.formatTime(root.trackNow, "HH:mm:ss") : "--:--:--"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body * 2.6
          font.bold: true
          font.letterSpacing: 1
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.ready
            ? Qt.formatDate(root.trackNow, "dddd d MMMM") + " · "
              + (root.hostWidget.trackZoneName ? root.hostWidget.trackZoneName + " " : "")
              + root.offsetLabel(root.trackOffset)
            : "Looking up circuit timezone…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSeparator { width: parent.width }

      // Details.
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.ready

        DetailRow {
          labelColor: root.dim
          valueColor: root.fg
          fontName: root.fontFamily
          label: "YOUR TIME"
          value: Qt.formatTime(new Date(root.nowMs), "HH:mm") + " · " + root.differenceLabel()
        }
        DetailRow {
          labelColor: root.dim
          valueColor: root.fg
          fontName: root.fontFamily
          label: "RACE · TRACK"
          value: root.raceTrackTime()
        }
        DetailRow {
          labelColor: root.dim
          valueColor: root.fg
          fontName: root.fontFamily
          label: "RACE · YOU"
          value: root.race ? Qt.formatDateTime(new Date(root.race.startMs), "ddd d MMM · HH:mm") : ""
        }
        DetailRow {
          labelColor: root.dim
          fontName: root.fontFamily
          label: "LIGHTS OUT"
          value: root.live ? "● LIVE" : "in " + root.countdown()
          valueColor: root.live ? root.f1Red : root.fg
        }
      }

      PanelSeparator { width: parent.width }

      // Bar icon choice, saved like the clock style.
      Item {
        width: parent.width
        height: iconChoices.height

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "BAR ICON"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }

        Row {
          id: iconChoices
          anchors.right: parent.right
          spacing: Style.space(6)

          Repeater {
            // nf-fa-flag_checkered / nf-md-web_clock
            model: [
              { value: "Flag", glyph: "\uf11e", label: "Checkered flag" },
              { value: "Globe", glyph: "\udb84\ude4a", label: "Globe with clock" }
            ]
            Rectangle {
              required property var modelData
              readonly property bool selected: root.barIcon === modelData.value
              width: Style.space(36)
              height: Style.space(28)
              radius: Style.space(3)
              color: selected ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16) : "transparent"
              border.width: 1
              border.color: selected ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
              Text {
                anchors.centerIn: parent
                text: parent.modelData.glyph
                color: parent.selected ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body * 1.15
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.persistSettings({ barIcon: parent.modelData.value })
              }
              Accessible.role: Accessible.RadioButton
              Accessible.name: modelData.label
              Accessible.checked: selected
            }
          }
        }
      }
    }
  }
}
