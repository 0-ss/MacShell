#!/usr/bin/env bash
# verify-screenshare.sh — confirm screen capture uses zero-copy dma-buf (not the
# SHM fallback that stalls the render loop and drops HDMI from 144Hz to 60).
#
# Run this, THEN start a screen share (Discord/Vesktop/browser/Zoom/OBS) and pick
# the 144Hz monitor. Watch the verdict. Ctrl-C to stop.
#
# PASS -> capture negotiated dma-buf; no render-loop stall; 144Hz holds.
# FAIL -> fell back to SHM (the bug). Two known signatures:
#   old: "Incompatible formats, renegotiate stream"  (10-bit/CM format mismatch)
#   new: "Out of buffers" + "DMA-BUF fixation failed" (buffer-alloc starvation)
set -uo pipefail
UNIT="xdg-desktop-portal-hyprland.service"

verdict="(no share seen yet)"
started=0

trap 'echo; echo "==================================================================";
      echo "FINAL VERDICT: $verdict"; exit 0' INT

echo "Watching $UNIT … now start a screen share and select the HDMI monitor."
echo "Press Ctrl-C when done to see the final verdict."
echo "-------------------------------------------------------------------"
journalctl --user -u "$UNIT" -f -n0 --output=cat 2>/dev/null | while IFS= read -r l; do
    case "$l" in
        *"[screencopy] Start"*|*"Sharing initialized"*)
            started=1; verdict="PASS ✅ (dma-buf held)"
            echo "····  capture starting — watching for SHM fallback…" ;;
        *"Out of buffers"*)
            echo "warn  ⚠️   $l" ;;
        *"fixation failed"*|*"DMA-BUF allocation failed"*|*"Incompatible formats"*|*"falling back to SHM"*)
            verdict="FAIL ❌ (fell back to SHM — render loop will stall)"
            echo "FAIL  ❌  $l" ;;
        *"wl_shm buffer which is legacy"*)
            [ "$started" = 1 ] && verdict="FAIL ❌ (SHM buffers in use — render loop will stall)"
            echo "FAIL  ❌  consumer is on SHM: $l" ;;
        *"Stream destroyed"*|*"Session destroyed"*)
            echo "----  share stopped ($verdict)"; started=0 ;;
    esac
done
