// The widgets MacShell adds to the desktop widgets: Batteries, Notes, Photos, Reminders, Alarms and Stocks.
// Their contents and the data they show live here; each one is drawn on a CardWidget (the same card, styles and
// Liquid Glass as the Calendar) by WidgetVisual.qml. Notes and reminders are plain files you can edit anywhere:
// ~/.config/macwidgets/notes.md and reminders.md.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Item {
    id: root
    visible: false
    property var host: null                  // the MacWidgets instance
    readonly property var hub: host ? host.hub : null
    readonly property var bar: hub ? hub.bar : null
    readonly property string fam: host ? host.fontFamily : "Open Runde"
    readonly property bool editing: host ? host.editing : false
    readonly property color accent: hub && hub.dock ? hub.dock.accent : "#0A84FF"
    readonly property string cfgDir: host ? host.configDir : Quickshell.env("HOME") + "/.config/macwidgets"
    readonly property bool asleep: false
    property var stockSymbols: ["AAPL", "NVDA", "^GSPC", "BTC-USD"]
    // data is only fetched for widgets that are on the desktop
    function wants(type) { return host ? (host.rev >= 0 && host.count(type) > 0) : false; }
    function comp(type) {
        return ({ batteries: cBatteries, notes: cNotes, photos: cPhotos, reminders: cReminders, alarms: cAlarms, stocks: cStocks })[type] || null;
    }

    // stocks (Yahoo chart API) every 10 min
    property var stocks: ({})
    readonly property bool wantsStocks: root.wants("stocks")
    Process {
        id: stockProc
        running: root.wantsStocks
        command: ["sh", "-c", "for s in \"$@\"; do curl -s --max-time 8 -A 'Mozilla/5.0' -G \"https://query1.finance.yahoo.com/v8/finance/chart/$s\" -d range=1d -d interval=15m "
            + "| jq -c --arg s \"$s\" '{s: $s, name: (.chart.result[0].meta.shortName // $s), p: .chart.result[0].meta.regularMarketPrice, pc: .chart.result[0].meta.chartPreviousClose, c: [.chart.result[0].indicators.quote[0].close[] | select(. != null)]}' 2>/dev/null; sleep 0.3; done", "sh"].concat(root.stockSymbols)
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, l = text.split("\n");
                for (var i = 0; i < l.length; i++) { try { var o = JSON.parse(l[i]); if (o && o.p) m[o.s] = o; } catch (e) {} }
                root.stocks = m;
            }
        }
    }
    Timer { interval: 10 * 60 * 1000; repeat: true; running: root.wantsStocks && !root.asleep; onTriggered: stockProc.running = true }

    // notes + reminders (plain files you can edit anywhere)
    FileView { id: notesFile; path: root.cfgDir + "/notes.md"; watchChanges: true; printErrors: false; onFileChanged: reload()
               onLoadFailed: setText("# Notes\n\nWrite anything here — it shows up on the desktop.\nOpen this file from the Notes widget.\n") }
    FileView { id: remFile; path: root.cfgDir + "/reminders.md"; watchChanges: true; printErrors: false; onFileChanged: reload()
               onLoadFailed: setText("- [ ] Try the new widgets\n- [x] Install MacShell\n- [ ] Click a circle to tick it off\n") }
    readonly property string notesText: notesFile.loaded ? notesFile.text() : ""
    readonly property var reminders: {
        var t = remFile.loaded ? remFile.text() : "", out = [], l = t.split("\n");
        for (var i = 0; i < l.length; i++) {
            var m = /^\s*[-*]\s*\[( |x|X)\]\s*(.*)$/.exec(l[i]);
            if (m) out.push({ line: i, done: m[1] !== " ", text: m[2] });
        }
        return out;
    }
    // The Repeater used to sit on the plain array, so rewriting the file rebuilt every row and the whole list
    // replayed its entry animation on every tick. This model is patched in place: only the row that changed moves.
    ListModel { id: remModel }
    property bool remReady: false
    function syncReminders() {
        var r = root.reminders, i, j;
        for (i = remModel.count - 1; i >= 0; i--) {
            var gone = true;
            for (j = 0; j < r.length; j++) if (r[j].text === remModel.get(i).text) { gone = false; break; }
            if (gone) remModel.remove(i);
        }
        for (var k = 0; k < r.length; k++) {
            if (k >= remModel.count || remModel.get(k).text !== r[k].text) {
                remModel.insert(k, { line: r[k].line, done: r[k].done, text: r[k].text, fresh: root.remReady });
            } else {
                if (remModel.get(k).done !== r[k].done) remModel.setProperty(k, "done", r[k].done);
                if (remModel.get(k).line !== r[k].line) remModel.setProperty(k, "line", r[k].line);
            }
        }
        while (remModel.count > r.length) remModel.remove(remModel.count - 1);
        if (r.length > 0) root.remReady = true;
    }
    onRemindersChanged: syncReminders()
    Component.onCompleted: syncReminders()
    function toggleReminder(lineNo) {
        var l = remFile.text().split("\n");
        if (lineNo < 0 || lineNo >= l.length) return;
        l[lineNo] = /\[ \]/.test(l[lineNo]) ? l[lineNo].replace("[ ]", "[x]") : l[lineNo].replace(/\[(x|X)\]/, "[ ]");
        remFile.setText(l.join("\n"));
        if (bar) bar.playSound("tink", 0.6);
    }
    function openFile(p) { Quickshell.execDetached(["xdg-open", p]); }
    // the Reminders editor writes the same markdown you would type by hand
    function addReminder(text) {
        var t = String(text || "").trim();
        if (t === "") return;
        var cur = remFile.loaded ? remFile.text() : "";
        if (cur !== "" && cur.charAt(cur.length - 1) !== "\n") cur += "\n";
        remFile.setText(cur + "- [ ] " + t + "\n");
        if (bar) bar.playSound("pop", 0.5);
    }
    function setReminderText(lineNo, text) {
        var l = remFile.text().split("\n");
        if (lineNo < 0 || lineNo >= l.length) return;
        var t = String(text || "").trim();
        if (t === "") { deleteReminder(lineNo); return; }
        l[lineNo] = l[lineNo].replace(/^(\s*[-*]\s*\[( |x|X)\]\s*).*$/, "$1" + t.replace(/\$/g, "$$$$"));
        remFile.setText(l.join("\n"));
    }
    function deleteReminder(lineNo) {
        var l = remFile.text().split("\n");
        if (lineNo < 0 || lineNo >= l.length) return;
        l.splice(lineNo, 1);
        remFile.setText(l.join("\n"));
        if (bar) bar.playSound("tink", 0.4);
    }


    // photos: a random picture from ~/Pictures (not screenshots / wallpapers), changes every 15 min
    property var photoList: []
    property int photoIdx: 0
    readonly property string photo: photoList.length ? photoList[photoIdx % photoList.length] : ""
    readonly property bool wantsPhotos: root.wants("photos")
    Process {
        running: root.wantsPhotos
        command: ["sh", "-c", "find -L \"$HOME/Pictures\" -maxdepth 4 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) "
            + "! -ipath '*screenshot*' ! -ipath '*/Wallpapers/*' ! -ipath '*/.cache/*' -size +60k 2>/dev/null | shuf -n 60"]
        stdout: StdioCollector { onStreamFinished: root.photoList = text.split("\n").filter(function (x) { return x !== ""; }) }
    }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: root.wantsPhotos && !root.asleep; onTriggered: root.photoIdx++ }

    // batteries: this Mac + anything UPower knows about (headsets, mice, keyboards…)
    readonly property var batteries: {
        var out = [], ds = UPower.devices.values;
        for (var i = 0; i < ds.length; i++) {
            var d = ds[i];
            if (!d.isPresent && !d.isLaptopBattery) continue;
            if (d.type === UPowerDeviceType.LinePower) continue;
            var p = d.percentage <= 1.0 ? d.percentage * 100 : d.percentage;
            if (!(p >= 0)) continue;
            out.push({ name: d.isLaptopBattery ? I18n.tr("MacBook") : (d.model || I18n.tr("Device")), pct: Math.round(p), laptop: d.isLaptopBattery,
                       charging: d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged,
                       kind: d.isLaptopBattery ? "laptop" : (/head|cloud|buds|pods|ear/i.test(d.model || "") ? "headphones" : (/mouse/i.test(d.model || "") ? "mouse" : "device")) });
        }
        out.sort(function (a, b) { return (b.laptop ? 1 : 0) - (a.laptop ? 1 : 0); });
        return out;
    }


    component WIcon: Canvas {
        id: wi
        property string kind: "sun"
        property color color: "white"
        property bool tinted: false         // monochrome (Tinted style)
        width: 24; height: 24
        onKindChanged: requestPaint()
        onColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            var s = Math.min(width, height) / 18; c.scale(s, s);
            var mono = wi.tinted, PI = Math.PI;
            var sunC = mono ? wi.color : "#FFD60A", cloudC = mono ? wi.color : "#F2F2F7", rainC = mono ? wi.color : "#64D2FF";
            c.lineCap = "round"; c.lineJoin = "round";
            function sun(x, y, r) {
                c.fillStyle = sunC; c.beginPath(); c.arc(x, y, r, 0, PI * 2); c.fill();
                c.strokeStyle = sunC; c.lineWidth = 1.3;
                for (var i = 0; i < 8; i++) { var a = i * PI / 4; c.beginPath(); c.moveTo(x + Math.cos(a) * (r + 1.6), y + Math.sin(a) * (r + 1.6)); c.lineTo(x + Math.cos(a) * (r + 3), y + Math.sin(a) * (r + 3)); c.stroke(); }
            }
            function moon(x, y, r) {
                c.fillStyle = mono ? wi.color : "#E5E5EA"; c.beginPath(); c.arc(x, y, r, 0, PI * 2); c.fill();
                c.globalCompositeOperation = "destination-out"; c.beginPath(); c.arc(x + r * 0.55, y - r * 0.4, r * 0.85, 0, PI * 2); c.fill();
                c.globalCompositeOperation = "source-over";
            }
            function cloud(x, y, k) {
                c.fillStyle = cloudC; c.beginPath();
                c.arc(x - 3.2 * k, y + 0.8 * k, 2.6 * k, 0, PI * 2); c.arc(x, y - 1.2 * k, 3.6 * k, 0, PI * 2); c.arc(x + 3.6 * k, y + 0.6 * k, 2.8 * k, 0, PI * 2);
                c.rect(x - 3.2 * k, y + 0.8 * k, 6.8 * k, 2.6 * k); c.fill();
            }
            var k = wi.kind;
            if (k === "sun") sun(9, 9, 3.8);
            else if (k === "moon") moon(9, 9, 5.2);
            else if (k === "partly") { sun(6.2, 6.4, 2.8); cloud(10.2, 11, 1.0); }
            else if (k === "partlynight") { moon(6.4, 6.2, 3.6); cloud(10.2, 11, 1.0); }
            else if (k === "cloud") cloud(9, 9.4, 1.15);
            else if (k === "fog") { cloud(9, 7.4, 1.0); c.strokeStyle = cloudC; c.lineWidth = 1.3; c.beginPath(); c.moveTo(3.5, 13.5); c.lineTo(14.5, 13.5); c.moveTo(5, 16); c.lineTo(13, 16); c.stroke(); }
            else if (k === "rain") { cloud(9, 7, 1.05); c.strokeStyle = rainC; c.lineWidth = 1.4; for (var i = 0; i < 3; i++) { c.beginPath(); c.moveTo(5.6 + i * 3.2, 12.2); c.lineTo(4.6 + i * 3.2, 15.6); c.stroke(); } }
            else if (k === "snow") { cloud(9, 7, 1.05); c.fillStyle = cloudC; for (var j = 0; j < 3; j++) { c.beginPath(); c.arc(5.4 + j * 3.4, 13.8 + (j % 2) * 1.6, 1.0, 0, PI * 2); c.fill(); } }
            else if (k === "storm") { cloud(9, 6.6, 1.05); c.fillStyle = sunC; c.beginPath(); c.moveTo(9.6, 10.6); c.lineTo(6.8, 14.4); c.lineTo(9, 14.4); c.lineTo(7.8, 17.4); c.lineTo(11.6, 13); c.lineTo(9.4, 13); c.lineTo(10.8, 10.6); c.closePath(); c.fill(); }
            else if (k === "laptop") { c.strokeStyle = wi.color; c.lineWidth = 1.4; c.beginPath(); c.rect(3.5, 4, 11, 7.6); c.stroke(); c.beginPath(); c.moveTo(1.5, 14); c.lineTo(16.5, 14); c.stroke(); }
            else if (k === "headphones") { c.strokeStyle = wi.color; c.lineWidth = 1.5; c.beginPath(); c.arc(9, 10, 6, PI, 0); c.stroke(); c.fillStyle = wi.color; c.fillRect(2.4, 10, 2.8, 5); c.fillRect(12.8, 10, 2.8, 5); }
            else if (k === "mouse") { c.strokeStyle = wi.color; c.lineWidth = 1.4; c.beginPath(); c.moveTo(9, 2.5); c.arcTo(14, 2.5, 14, 8, 4.5); c.arcTo(14, 15.5, 9, 15.5, 4.5); c.arcTo(4, 15.5, 4, 8, 4.5); c.arcTo(4, 2.5, 9, 2.5, 4.5); c.stroke(); c.beginPath(); c.moveTo(9, 3); c.lineTo(9, 7); c.stroke(); }
            else { c.strokeStyle = wi.color; c.lineWidth = 1.4; c.beginPath(); c.rect(3, 5, 12, 8); c.stroke(); }
        }
    }

    component Spark: Canvas {
        id: sp
        property var values: []
        property real base: 0
        property color color: "#30D158"
        onValuesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            var v = sp.values; if (!v || v.length < 2) return;
            var lo = Math.min.apply(null, v.concat([sp.base || v[0]])), hi = Math.max.apply(null, v.concat([sp.base || v[0]])), rg = (hi - lo) || 1;
            function px(i) { return i / (v.length - 1) * width; }
            function py(x) { return height - 2 - (x - lo) / rg * (height - 4); }
            if (sp.base) { c.strokeStyle = Qt.rgba(1, 1, 1, 0.3); c.setLineDash([2, 3]); c.lineWidth = 1; c.beginPath(); c.moveTo(0, py(sp.base)); c.lineTo(width, py(sp.base)); c.stroke(); c.setLineDash([]); }
            c.strokeStyle = sp.color; c.lineWidth = 1.8; c.lineJoin = "round"; c.beginPath();
            for (var i = 0; i < v.length; i++) { if (i === 0) c.moveTo(px(i), py(v[i])); else c.lineTo(px(i), py(v[i])); }
            c.stroke();
        }
    }

    Component {
        id: cBatteries
        Item {
            readonly property var ctx: parent ? parent.ctx : null
            readonly property bool med: ctx && ctx.size !== "s"
            readonly property var list: root.batteries
            function ringColor(b) { return ctx && ctx.mono ? ctx.fg : (b.pct <= 20 && !b.charging ? "#FF453A" : "#30D158"); }
            // small: up to four rings
            Grid {
                visible: !parent.med
                anchors.centerIn: parent
                // one battery is a single column, otherwise the empty second column throws the ring off centre
                columns: Math.min(2, Math.max(1, Math.min(4, list.length)))
                spacing: 14
                Repeater {
                    model: Math.max(1, Math.min(4, list.length))
                    delegate: Item {
                        required property int index
                        readonly property var b: list[index]
                        width: 58; height: 58
                        Canvas {
                            anchors.fill: parent
                            property real pct: b ? b.pct : 0
                            property color col: b ? ringColor(b) : "gray"
                            onPctChanged: requestPaint(); onColChanged: requestPaint()
                            onPaint: {
                                var c = getContext("2d"); c.reset(); var r = width / 2 - 3;
                                c.lineWidth = 5; c.lineCap = "round";
                                c.strokeStyle = Qt.rgba(1, 1, 1, 0.16); c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke();
                                c.strokeStyle = col; c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * pct / 100); c.stroke();
                            }
                        }
                        WIcon { anchors.centerIn: parent; width: 22; height: 22; anchors.verticalCenterOffset: (b && b.charging) ? -4 : 0; kind: b ? b.kind : "laptop"; color: ctx ? ctx.fg : "white"; tinted: true }
                        Text {
                            visible: !!(b && b.charging)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 13
                            text: "\u26A1"; color: ctx && ctx.mono ? ctx.fg : "#30D158"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 10
                        }
                    }
                }
            }
            // medium: list rows
            Column {
                visible: parent.med
                anchors.fill: parent
                spacing: 8
                Repeater {
                    model: Math.min(4, list.length)
                    delegate: Item {
                        required property int index
                        readonly property var b: list[index]
                        width: parent.width; height: 26
                        WIcon { anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; kind: b.kind; color: ctx ? ctx.fg : "white"; tinted: true }
                        Text { x: 32; anchors.verticalCenter: parent.verticalCenter; width: 110; elide: Text.ElideRight; text: b.name; color: ctx ? ctx.fg : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                        Rectangle {
                            x: 150; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 150 - 54; height: 7; radius: 3.5; color: Qt.rgba(1, 1, 1, 0.16)
                            Rectangle { width: parent.width * b.pct / 100; height: parent.height; radius: 3.5; color: ringColor(b) }
                        }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (b.charging ? "⚡" : "") + b.pct + "%"; color: ctx ? ctx.fg : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }
    Component {
        id: cNotes
        Item {
            readonly property var ctx: parent ? parent.ctx : null
            Row {
                id: nHead
                spacing: 6
                Rectangle { width: 18; height: 18; radius: 5; color: ctx && ctx.mono ? ctx.fg : "#FFD60A"; anchors.verticalCenter: parent.verticalCenter
                            Rectangle { x: 3; y: 4; width: 12; height: 1.6; color: ctx && ctx.mono ? root.accent : "white" } }
                Text { text: I18n.tr("Notes"); color: ctx && ctx.mono ? ctx.fg : "#FFD60A"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 14; font.weight: Font.Bold }
            }
            Text {
                y: nHead.height + 8
                width: parent.width; height: parent.height - y
                clip: true
                text: root.notesText.replace(/^#+\s*/gm, "")
                wrapMode: Text.Wrap; elide: Text.ElideRight
                color: ctx ? ctx.fg : "white"; font.family: root.fam; font.pixelSize: 13; lineHeight: 1.12
            }
            MouseArea { anchors.fill: parent; enabled: !root.editing; cursorShape: Qt.PointingHandCursor; onClicked: root.openFile(root.cfgDir + "/notes.md") }
        }
    }
    Component {
        id: cPhotos
        Item {
            readonly property var ctx: parent ? parent.ctx : null
            // full bleed: the photo fills the widget (the Loader for photos has no margins)
            Item { id: pMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 22; color: "black" } }
            Image {
                id: pImg
                anchors.fill: parent
                source: root.photo !== "" ? "file://" + root.photo : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                sourceSize: Qt.size(720, 720)
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 700 } }
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: pMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 54; radius: 22
                gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) } }
            }
            Text {
                x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                text: root.photoList.length ? I18n.tr("Featured Photo") : I18n.tr("Add pictures to ~/Pictures")
                color: "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold
            }
            MouseArea { anchors.fill: parent; enabled: !root.editing && root.photo !== ""; cursorShape: Qt.PointingHandCursor
                        onClicked: root.openFile(root.photo); onDoubleClicked: root.photoIdx++ }
        }
    }
    Component {
        id: cReminders
        Item {
            readonly property var ctx: parent ? parent.ctx : null
            readonly property var open: root.reminders.filter(function (r) { return !r.done; })
            readonly property color blue: ctx && ctx.mono ? ctx.fg : "#0A84FF"
            Item {
                id: rHead
                width: parent.width
                height: cnt.height
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - cnt.width - addBtn.width - 14; elide: Text.ElideRight
                    text: I18n.tr("Reminders"); color: blue; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 14; font.weight: Font.Bold
                }
                MorphText {
                    id: cnt
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.open.length; duration: 420; animateWidth: false
                    color: blue; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 22; font.weight: Font.Bold
                }
                // + — add one without leaving the widget. It lives beside the count, never on top of it,
                // and fades in on hover the way macOS reveals its controls.
                Rectangle {
                    id: addBtn
                    anchors.right: cnt.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    visible: opacity > 0.01
                    opacity: root.editing ? 0 : ((headHover.hovered || adding) ? 1 : 0)
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    color: addMa.containsMouse ? Qt.rgba(blue.r, blue.g, blue.b, 0.22) : "transparent"
                    rotation: adding ? 45 : 0
                    Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    scale: addMa.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    Rectangle { anchors.centerIn: parent; width: 11; height: 1.7; radius: 1; color: blue }
                    Rectangle { anchors.centerIn: parent; width: 1.7; height: 11; radius: 1; color: blue }
                    MouseArea {
                        id: addMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { adding = !adding; if (adding) newInput.forceActiveFocus(); }
                    }
                }
                HoverHandler { id: headHover }
            }
            property bool adding: false
            property int editingLine: -1
            Flickable {
                id: remFlick
                y: rHead.height + 6
                width: parent.width
                height: parent.height - y
                clip: true
                contentHeight: remCol.height
                boundsBehavior: Flickable.StopAtBounds
                // only takes over the drag when there is actually something to scroll, so the widget itself
                // stays draggable from its list whenever everything already fits
                interactive: !root.editing && contentHeight > height + 2
              Column {
                id: remCol
                width: parent.width
                spacing: 7
                // new reminder
                Item {
                    width: parent.width
                    height: adding ? 22 : 0
                    clip: true
                    opacity: adding ? 1 : 0
                    Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"; border.width: 1.5; border.color: ctx ? ctx.fg2 : "white"
                    }
                    TextInput {
                        id: newInput
                        x: 24; width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        color: ctx ? ctx.fg : "white"; font.family: root.fam; font.pixelSize: 13
                        selectByMouse: false
                        onAccepted: { root.addReminder(text); text = ""; }
                        Keys.onEscapePressed: { text = ""; adding = false; }
                        Text { visible: parent.text === ""; text: I18n.tr("New Reminder"); color: ctx ? ctx.fg2 : "grey"; font: parent.font }
                    }
                }
                Repeater {
                    model: remModel
                    delegate: Row {
                        id: remRow
                        required property var model
                        readonly property var modelData: remRow.model
                        required property int index
                        spacing: 8
                        width: parent.width
                        // the first list staggers in; a row added later springs in on its own, and nothing else moves
                        property real inT: 0
                        opacity: inT
                        transform: Translate { y: (1 - remRow.inT) * 8 }
                        Component.onCompleted: remRow.model.fresh ? rowSolo.start() : rowIn.start()
                        SequentialAnimation {
                            id: rowIn
                            PauseAnimation { duration: Math.min(300, remRow.index * 45) }
                            NumberAnimation { target: remRow; property: "inT"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                        }
                        NumberAnimation { id: rowSolo; target: remRow; property: "inT"; from: 0; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                        Rectangle {
                            id: tick
                            width: 16; height: 16; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property bool done: modelData.done
                            property real fill: done ? 1 : 0
                            Behavior on fill { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
                            color: Qt.rgba(blue.r, blue.g, blue.b, fill)
                            border.width: 1.5
                            border.color: done ? blue : (ctx ? ctx.fg2 : "white")
                            Behavior on border.color { ColorAnimation { duration: 300 } }
                            // the press itself: a quick squeeze that springs back
                            property real press: 0
                            scale: (0.86 + 0.14 * Math.max(fill, 1 - fill * 0)) * (1 - 0.18 * press) + (fill > 0 ? 0 : 0)
                            SequentialAnimation {
                                id: tickPop
                                NumberAnimation { target: tick; property: "press"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                                NumberAnimation { target: tick; property: "press"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3.0 }
                            }
                            // the tick draws itself in
                            Canvas {
                                id: tickMark
                                anchors.centerIn: parent
                                width: 11; height: 11
                                property real draw: tick.fill
                                onDrawChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.reset();
                                    if (draw <= 0.01) return;
                                    c.strokeStyle = "white"; c.lineWidth = 1.9; c.lineCap = "round"; c.lineJoin = "round";
                                    var p = [[1.6, 5.6], [4.3, 8.4], [9.4, 2.6]];
                                    var d = Math.max(0, Math.min(1, (draw - 0.15) / 0.85));
                                    c.beginPath(); c.moveTo(p[0][0], p[0][1]);
                                    var t1 = Math.min(1, d / 0.4);
                                    c.lineTo(p[0][0] + (p[1][0] - p[0][0]) * t1, p[0][1] + (p[1][1] - p[0][1]) * t1);
                                    if (d > 0.4) {
                                        var t2 = (d - 0.4) / 0.6;
                                        c.lineTo(p[1][0] + (p[2][0] - p[1][0]) * t2, p[1][1] + (p[2][1] - p[1][1]) * t2);
                                    }
                                    c.stroke();
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                enabled: !root.editing; cursorShape: Qt.PointingHandCursor
                                onClicked: { tickPop.restart(); root.toggleReminder(modelData.line); if (root.bar) root.bar.playSound("tink", 0.5); }
                            }
                        }
                        Item {
                            width: parent.width - 24
                            height: Math.max(rowTxt.implicitHeight, 18)
                            anchors.verticalCenter: parent.verticalCenter
                            // Nothing here is a text field, so a click can never leave text selected on the desktop.
                            // Renaming lives in the Reminders app, which this row opens.
                            HoverHandler { id: rowHover; enabled: !root.editing }
                            Text {
                                id: rowTxt
                                width: parent.width - (rowHover.hovered ? 20 : 0); elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.text; font.strikeout: modelData.done
                                color: ctx ? (modelData.done ? ctx.fg2 : ctx.fg) : "white"
                                font.family: root.fam; font.pixelSize: 13
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent; anchors.rightMargin: 22
                                enabled: !root.editing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.openFile(root.cfgDir + "/reminders.md");
                                }
                            }
                            Text {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: "\u00D7"; color: ctx ? ctx.fg2 : "grey"; font.family: root.fam; font.pixelSize: 15
                                opacity: rowHover.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -5
                                    enabled: rowHover.hovered
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.deleteReminder(modelData.line)
                                }
                            }
                        }
                    }
                }
              }
            }
            // the header opens the Reminders app, not a text editor
            MouseArea {
                anchors.fill: rHead; enabled: !root.editing; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.openFile(root.cfgDir + "/reminders.md");
                }
            }
        }
    }
    Component {
        id: cAlarms
        Item {
            id: ca
            readonly property var ctx: parent ? parent.ctx : null
            readonly property var ck: root.hub ? root.hub.clock : null
            readonly property string size: ctx ? ctx.size : "s"
            readonly property color fg: ctx ? ctx.fg : "white"
            readonly property color fg2: ctx ? ctx.fg2 : Qt.rgba(1, 1, 1, 0.6)
            readonly property color orange: ctx && ctx.mono ? fg : "#FF9F0A"
            readonly property bool hasTimer: ck !== null && ck.timerActive
            readonly property bool hasSw: ck !== null && ck.swActive
            readonly property bool live: hasTimer || hasSw
            readonly property var alarmList: ck ? ck.alarms : []
            readonly property int maxAlarms: size === "l" ? (live ? 4 : 6) : (size === "m" ? 3 : 1)

            // ── live activity (timer ring / stopwatch) ──
            Item {
                id: liveBox
                visible: ca.live
                width: ca.size === "m" ? 140 : parent.width
                height: ca.size === "s" ? parent.height : (ca.size === "m" ? parent.height : 132)
                // timer
                Item {
                    visible: ca.hasTimer
                    anchors.fill: parent
                    readonly property real remain: ca.ck ? ca.ck.timerLeft() : 0
                    readonly property real frac: ca.ck && ca.ck.timer.total > 0 ? remain / ca.ck.timer.total : 0
                    Canvas {
                        id: tring
                        width: Math.min(parent.width, parent.height) - (ca.size === "l" ? 12 : 4); height: width
                        anchors.left: ca.size === "l" ? parent.left : undefined
                        anchors.horizontalCenter: ca.size === "l" ? undefined : parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        property real f: parent.frac
                        property color ink: ca.orange
                        Behavior on f { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }
                        onFChanged: requestPaint()
                        onInkChanged: requestPaint()
                        onPaint: {
                            var c = getContext("2d"); c.reset();
                            var lw = width * 0.07, r = width / 2 - lw / 2;
                            c.lineWidth = lw; c.lineCap = "round";
                            c.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.3);
                            c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke();
                            c.strokeStyle = ink;
                            c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.0001, f)); c.stroke();
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: ca.ck ? ca.ck.fmtDur(parent.parent.parent.remain) : ""; color: ca.fg; font.family: root.fam; font.pixelSize: tring.width * 0.2; font.weight: Font.Medium; font.features: { "tnum": 1 } }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: ca.ck ? (ca.ck.timer.state === "paused" ? I18n.tr("Paused") : (ca.ck.timer.label || I18n.tr("Timer"))) : ""; color: ca.fg2; font.family: root.fam; font.pixelSize: Math.max(10, tring.width * 0.085) }
                        }
                    }
                    // large: a second line with the stopwatch next to the ring
                }
                // stopwatch (when no timer, or next to it on the large size)
                Column {
                    visible: ca.hasSw && (!ca.hasTimer || ca.size === "l")
                    anchors.verticalCenter: parent.verticalCenter
                    x: ca.hasTimer ? tring.width + 22 : (ca.size === "s" ? 0 : 6)
                    width: parent.width - x
                    spacing: 2
                    Row {
                        spacing: 5
                        ClockGlyph { anchors.verticalCenter: parent.verticalCenter; kind: "stopwatch"; color: ca.orange; width: 14; height: 14 }
                        Text { text: I18n.tr("Stopwatch"); color: ca.orange; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 14
                        text: ca.ck ? ca.ck.fmtSw(ca.ck.swElapsed()).replace(/,\d\d$/, "") : ""
                        color: ca.fg; font.family: root.fam; font.pixelSize: ca.size === "s" ? 34 : 30; font.weight: Font.Medium; font.features: { "tnum": 1 }
                    }
                    Text { text: ca.ck && ca.ck.sw.running ? I18n.tr("Running") : I18n.tr("Paused"); color: ca.fg2; font.family: root.fam; font.pixelSize: 12 }
                }
            }

            // ── alarms ──
            Column {
                id: alarmCol
                visible: !(ca.size === "s" && ca.live)
                x: ca.size === "m" && ca.live ? 156 : 0
                y: ca.size === "l" && ca.live ? liveBox.height + 12 : 0
                width: parent.width - x
                spacing: ca.size === "s" ? 2 : 6
                Row {
                    visible: ca.size !== "s" || ca.alarmList.length > 0
                    spacing: 5
                    ClockGlyph { anchors.verticalCenter: parent.verticalCenter; kind: "alarm"; color: ca.orange; width: 14; height: 14 }
                    Text { text: I18n.tr("Alarms"); color: ca.orange; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                }
                Repeater {
                    model: ca.alarmList.slice(0, ca.maxAlarms)
                    delegate: Item {
                        id: arow
                        required property var modelData
                        width: alarmCol.width
                        height: ca.size === "s" ? 120 : 34
                        // small: one big alarm
                        Column {
                            visible: ca.size === "s"
                            y: 6
                            Text {
                                text: ca.ck ? ca.ck.fmtHM(arow.modelData.h, arow.modelData.m) + (ca.ck.ampm(arow.modelData.h) ? " " + ca.ck.ampm(arow.modelData.h) : "") : ""
                                color: arow.modelData.on ? ca.fg : ca.fg2
                                font.family: root.fam; font.pixelSize: 36; font.weight: Font.Light
                            }
                            Text { text: (arow.modelData.label || I18n.tr("Alarm")) + (arow.modelData.days.length ? ", " + ca.ck.repeatText(arow.modelData.days) : ""); color: ca.fg2; font.family: root.fam; font.pixelSize: 12; width: alarmCol.width; elide: Text.ElideRight }
                        }
                        Column {
                            visible: ca.size !== "s"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - asw.width - 8
                            Text {
                                text: ca.ck ? ca.ck.fmtHM(arow.modelData.h, arow.modelData.m) + (ca.ck.ampm(arow.modelData.h) ? " " + ca.ck.ampm(arow.modelData.h) : "") : ""
                                color: arow.modelData.on ? ca.fg : ca.fg2
                                font.family: root.fam; font.pixelSize: 17; font.weight: Font.Medium
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text { width: parent.width; elide: Text.ElideRight; text: (arow.modelData.label || I18n.tr("Alarm")) + (arow.modelData.days.length ? ", " + ca.ck.repeatText(arow.modelData.days) : ""); color: ca.fg2; font.family: root.fam; font.pixelSize: 11 }
                        }
                        // on / off
                        LiquidSwitch {
                            id: asw
                            anchors.right: parent.right
                            anchors.verticalCenter: ca.size === "s" ? undefined : parent.verticalCenter
                            anchors.bottom: ca.size === "s" ? parent.bottom : undefined
                            width: 36; height: 21
                            enabled: !root.editing
                            checked: arow.modelData.on
                            accent: ctx && ctx.mono ? ca.fg : "#30D158"
                            offColor: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                            material: root.bar ? root.bar.material : "liquid"
                            onToggled: v => { if (ca.ck) ca.ck.setAlarmOn(arow.modelData.id, v); }
                        }
                    }
                }
                Text {
                    visible: ca.alarmList.length === 0
                    text: ca.size === "s" && !ca.live ? I18n.tr("No Alarms") : I18n.tr("No alarms")
                    color: ca.fg2; font.family: root.fam; font.pixelSize: ca.size === "s" ? 15 : 13
                }
            }
            // anywhere else: open the Clock app
            MouseArea {
                z: -1; anchors.fill: parent; enabled: !root.editing; cursorShape: Qt.PointingHandCursor
                onClicked: if (ca.ck) ca.ck.open(ca.hasTimer ? "timers" : (ca.hasSw ? "stopwatch" : "alarms"))
            }
        }
    }
    Component {
        id: cStocks
        Item {
            readonly property var ctx: parent ? parent.ctx : null
            readonly property bool med: ctx && ctx.size !== "s"
            readonly property var syms: root.stockSymbols
            function chg(q) { return q && q.pc ? (q.p - q.pc) / q.pc * 100 : 0; }
            function col(q) { return ctx && ctx.mono ? ctx.fg : (chg(q) >= 0 ? "#30D158" : "#FF453A"); }
            // small: first symbol, big
            Column {
                visible: !parent.med
                anchors.fill: parent
                spacing: 2
                readonly property var q: root.stocks[syms[0]]
                Text { text: syms[0]; color: ctx ? ctx.fg : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 16; font.weight: Font.Bold }
                Text { width: parent.width; elide: Text.ElideRight; text: parent.q ? parent.q.name : I18n.tr("Loading…"); color: ctx ? ctx.fg2 : "white"; font.family: root.fam; font.pixelSize: 11 }
                Spark { width: parent.width; height: 52; values: parent.q ? parent.q.c : []; base: parent.q ? parent.q.pc : 0; color: parent.parent.col(parent.q) }
                Text { text: parent.q ? parent.q.p.toFixed(2) : "--"; color: ctx ? ctx.fg : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 18; font.weight: Font.DemiBold }
                Text { text: parent.q ? (parent.parent.chg(parent.q) >= 0 ? "+" : "") + parent.parent.chg(parent.q).toFixed(2) + "%" : ""; color: parent.parent.col(parent.q); font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
            }
            // medium: watchlist
            Column {
                visible: parent.med
                anchors.fill: parent
                spacing: 4
                Repeater {
                    model: Math.min(4, syms.length)
                    delegate: Item {
                        required property int index
                        readonly property var q: root.stocks[syms[index]]
                        width: parent.width; height: 32
                        Column {
                            width: 110; anchors.verticalCenter: parent.verticalCenter
                            Text { text: syms[index]; color: ctx ? ctx.fg : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.Bold }
                            Text { width: 110; elide: Text.ElideRight; text: q ? q.name : ""; color: ctx ? ctx.fg2 : "white"; font.family: root.fam; font.pixelSize: 10 }
                        }
                        Spark { x: 118; width: parent.width - 118 - 96; height: 24; anchors.verticalCenter: parent.verticalCenter; values: q ? q.c : []; base: q ? q.pc : 0; color: col(q) }
                        Column {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            Text { anchors.right: parent.right; text: q ? q.p.toFixed(2) : "--"; color: ctx ? ctx.fg : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                            Rectangle {
                                anchors.right: parent.right; width: pct.implicitWidth + 10; height: 16; radius: 4; color: col(q)
                                Text { id: pct; anchors.centerIn: parent; text: q ? (chg(q) >= 0 ? "+" : "") + chg(q).toFixed(2) + "%" : ""; color: ctx && ctx.mono ? root.accent : "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 10; font.weight: Font.Bold }
                            }
                        }
                    }
                }
            }
        }
    }
}
