// LiveWall — the animated wallpaper (video) for the Liquid Glass backdrops. The glass of the Dock, the menus, the widgets and the
// Settings window refracts a picture of the wallpaper; for an animated wallpaper this item plays a video (muted) on top of that
// picture, so the glass shows the wallpaper moving in real time.
// `video` is what the shell hands in as bar.glassVideo: "" while "Animated wallpaper in glass" is off (the default), otherwise a small
// 720 px / 30 fps copy of the wallpaper. With `video` empty, `live` false, or the wallpaper a still picture again, the Loader is inactive
// and no decoder exists at all. `paused` keeps the decoder idle (desktop covered by windows, Game Mode) without tearing it down.
import QtQuick
import QtMultimedia

Item {
    id: lw
    property string video: ""        // absolute path of the video wallpaper, "" = a still picture
    property bool live: false        // real-time glass switched on
    property bool paused: false      // e.g. the desktop is completely covered by windows
    readonly property bool active: live && video !== ""

    Loader {
        anchors.fill: parent
        active: lw.active
        sourceComponent: Item {
            id: box
            readonly property bool run: !lw.paused
            onRunChanged: { if (run) mp.play(); else mp.pause(); }
            MediaPlayer {
                id: mp
                source: "file://" + lw.video
                loops: MediaPlayer.Infinite
                videoOutput: vo
                Component.onCompleted: { if (box.run) play(); }
            }
            VideoOutput {
                id: vo
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                // nothing is drawn until the first frame has arrived, so the still picture underneath never flashes
                visible: mp.playbackState !== MediaPlayer.StoppedState && mp.hasVideo
            }
        }
    }
}
