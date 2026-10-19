// One desktop widget's content (Weather / Calendar / Clock / Player). Used by MacWidgets.qml for the desktop layer and by
// MacBar.qml to mirror the widgets into the Liquid Glass backdrop, so a menu refracts them together with the live windows.
import QtQuick
import Quickshell.Services.Mpris

Item {
    id: v
    required property var host           // the MacWidgets instance (data, glass state, wallpaper lookup)
    property string wtype: "weather"
    property string wstyle: "liquid"
    property string wsize: "small"
    property string wmode: "auto"
    property string wsrc: ""             // image widget: path of the picture
    property real sx: 0                  // position on the screen (the glass uses it to find the wallpaper behind the widget)
    property real sy: 0
    property string sname: ""            // screen name
    property real sw: 1920
    property real sh: 1080
        Component {
            id: weatherVisual
            WeatherWidget {
                scaleF: host.widgetScale
                style: wstyle
                size: wsize
                fam: host.fontFamily
                screenX: v.sx; screenY: v.sy
                city: host.wxCity
                located: host.wxLocated
                hasData: host.wxReady
                temp: host.wxTemp
                hi: host.wxHi
                lo: host.wxLo
                cond: host.wxReady ? host.wxInfo.t : (host.wxError !== "" ? "Unavailable" : "Loading…")
                kind: host.wxReady ? host.wxInfo.k : "cloud"
                isDay: host.wxDay
                hourly: host.wxHourly
                daily: host.wxDaily
                glassReady: host.glassState === "ready"
                shaderUrl: "file://" + host.glassShaderOut
                wallUrl: host.fileUrl(host.wallpaperFor(v.sname))
                screenW: v.sw
                screenH: v.sh
                glassOpacity: host.glassOpacity
                glassBlur: host.glassBlur
                glassLiquid: host.glassLiquid
                glassRim: host.glassRim
                borderTint: host.borderTint
                glassGrain: host.glassGrain
                darkGlass: host.darkGlass
                editing: host.editing
                onGlassFailed: host.glassState = "failed"
            }
        }
        Component {
            id: calendarVisual
            CalendarWidget {
                scaleF: host.widgetScale
                style: wstyle
                size: wsize
                mode: wmode
                fam: host.fontFamily
                screenX: v.sx; screenY: v.sy
                weekStart: 0
                glassReady: host.glassState === "ready"
                shaderUrl: "file://" + host.glassShaderOut
                wallUrl: host.fileUrl(host.wallpaperFor(v.sname))
                screenW: v.sw
                screenH: v.sh
                glassOpacity: host.glassOpacity
                glassBlur: host.glassBlur
                glassLiquid: host.glassLiquid
                glassRim: host.glassRim
                borderTint: host.borderTint
                glassGrain: host.glassGrain
                darkGlass: host.darkGlass
                editing: host.editing
                onGlassFailed: host.glassState = "failed"
            }
        }
        Component {
            id: clockVisual
            ClockWidget {
                scaleF: host.widgetScale
                style: wstyle
                size: wsize
                fam: host.fontFamily
                screenX: v.sx; screenY: v.sy
                glassReady: host.glassState === "ready"
                shaderUrl: "file://" + host.glassShaderOut
                wallUrl: host.fileUrl(host.wallpaperFor(v.sname))
                screenW: v.sw
                screenH: v.sh
                glassOpacity: host.glassOpacity
                glassBlur: host.glassBlur
                glassLiquid: host.glassLiquid
                glassRim: host.glassRim
                borderTint: host.borderTint
                glassGrain: host.glassGrain
                darkGlass: host.darkGlass
                preview: false
                editing: host.editing
                onGlassFailed: host.glassState = "failed"
            }
        }
        Component {
            id: playerVisual
            PlayerWidget {
                scaleF: host.widgetScale
                style: wstyle
                size: wsize
                contentScale: host.playerScale
                fam: host.fontFamily
                screenX: v.sx; screenY: v.sy
                hasPlayer: host.player !== null
                title: host.player ? host.player.trackTitle : ""
                artist: host.player ? host.player.trackArtist : ""
                album: host.player ? host.player.trackAlbum : ""
                artUrl: host.player ? host.player.trackArtUrl : ""
                playing: host.player ? host.player.isPlaying : false
                shuffle: (host.player && host.player.shuffleSupported) ? host.player.shuffle : false
                canShuffle: host.player !== null && host.player.shuffleSupported
                loop: (host.player && host.player.loopSupported)
                      ? (host.player.loopState === MprisLoopState.Track ? 1 : (host.player.loopState === MprisLoopState.Playlist ? 2 : 0)) : 0
                canLoop: host.player !== null && host.player.loopSupported
                position: (host.player && host.player.positionSupported) ? host.player.position : 0
                length: (host.player && host.player.lengthSupported) ? host.player.length : 0
                canSeek: host.player !== null && host.player.canSeek && host.player.positionSupported && host.player.lengthSupported
                lyrics: host.lyricsLines
                lyricsState: host.lyricsState
                lyricsSynced: host.lyricsSynced
                onLyricsToggled: on => host.lyricsWanted = on
                glassReady: host.glassState === "ready"
                shaderUrl: "file://" + host.glassShaderOut
                wallUrl: host.fileUrl(host.wallpaperFor(v.sname))
                screenW: v.sw
                screenH: v.sh
                glassOpacity: host.glassOpacity
                glassBlur: host.glassBlur
                glassLiquid: host.glassLiquid
                glassRim: host.glassRim
                borderTint: host.borderTint
                glassGrain: host.glassGrain
                darkGlass: host.darkGlass
                editing: host.editing
                onSeek: seconds => { if (host.player && host.player.canSeek) host.player.position = seconds; }
                onTogglePlaying: { if (host.player && host.player.canTogglePlaying) host.player.togglePlaying(); }
                onNextTrack: { if (host.player && host.player.canGoNext) host.player.next(); }
                onPreviousTrack: { if (host.player && host.player.canGoPrevious) host.player.previous(); }
                onToggleShuffle: { if (host.player && host.player.shuffleSupported) host.player.shuffle = !host.player.shuffle; }
                onCycleLoop: {
                    if (!host.player || !host.player.loopSupported) return;
                    // off -> repeat all -> repeat song -> off
                    var ls = host.player.loopState;
                    host.player.loopState = ls === MprisLoopState.None ? MprisLoopState.Playlist
                                          : (ls === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None);
                }
                onGlassFailed: host.glassState = "failed"
            }
        }
        Component {
            id: imageVisual
            ImageWidget {
                size: wsize
                borderTint: host.borderTint
                scaleF: host.widgetScale
                fam: host.fontFamily
                screenX: v.sx; screenY: v.sy
                source: host.fileUrl(v.wsrc)
                darkGlass: host.darkGlass
                editing: host.editing
            }
        }
        Loader {
            id: visual
            anchors.fill: parent
            sourceComponent: wtype === "calendar" ? calendarVisual
                           : (wtype === "clock" ? clockVisual
                           : (wtype === "player" ? playerVisual
                           : (wtype === "image" ? imageVisual : weatherVisual)))
        }
}
