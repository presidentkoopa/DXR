# 14 — Replay & capture (the watchable file)

A shareable, watchable recording of a run — **stabilized so it's not nauseating**, output
as a video file.

## The hard rule

**Never touch the live in-headset view.** The player plays raw VR, unmodified. All
stabilization is **export-only.** There are two separate cameras — the headset (raw, hands
off) and the export cam (stabilized) — and the export cam only runs on the offline pass.
The game is never "fixed" under the player; a clean file is produced *after*.

## The spec

- **Output = a video file**, not a live overlay.
- **Roll-locked** — the horizon never tilts. Zero roll, always. This is the single biggest
  thing that makes VR footage watchable.
- **Pan + tilt allowed** — the camera follows where you looked (yaw + pitch) but through a
  **low-pass filter / spring-damper**, so fast head jerks become a glide. "Pan and scan,"
  smoothed.
- **Rendered offline** — so it costs nothing during play and the live view is never
  modified.

## How it works

1. **During play (invisible, cheap):** log the head pose each tick — position, yaw, pitch;
   **roll is discarded** — plus whatever the replay needs (demo / game state). Background,
   no perf hit, no visible change.
2. **On export (offline):** replay the run and render a dedicated **cinema camera** whose
   transform = logged position + *smoothed* yaw/pitch, **roll forced to 0**. Dump the frames
   and encode to a video file.

The live game and the export cam are fully decoupled; the stabilization is math applied to
a logged pose on a pass that happens when you're not playing.

## The camera math

- `roll = 0` — horizon lock. Do only this and the footage is already far better.
- position + yaw + pitch through a tunable smoothing filter (spring-damper / low-pass).
- optional slightly wider FOV so quick turns read gently.
- net effect: the viewer sees what you engaged with, smoothly, without the tilt.

## Why stabilized-FPV (not a 3rd-person drone) for *this* game

It **shows the hands.** The viewer watches you draw the sigil, crack the whip, fan the
revolver — from your seat. That's the whole selling point of a gesture-driven game; a
3rd-person cam hides it. (A 3rd-person drone option can still exist later — see open
questions — but FPV-stabilized is the default because it showcases the gestures.)

## The one real lift

**Offline video encode.** The engine has no native video encoder — the realistic paths are
frame-dump → ffmpeg, or embedding an encoder in the C++ (heavier, but yours to build). The
pose-logging and the stabilized camera transform are the easy parts; the encode is the
work.

## Ties in

- The **host commentary** + the **SDF score bug / lower-third** can be composited onto the
  export → a broadcast-framed highlight reel ([13](13_arenas-and-run.md) game-show DNA).
- Shareable runs = virality, the social loop a stylish arcade roguelite lives on.

## Open questions

- Encode path: external ffmpeg pipe vs. embedded encoder.
- Smoothing strength — a tunable (comfort ↔ responsiveness).
- Offer a 3rd-person drone as an *alternate* export mode, or FPV-stabilized only?
- Replay fidelity: does the offline pass re-render from logged pose, or is the pose enough
  to drive a full re-sim? (Ties to whether VR pose is added to the demo stream.)
