<img src="assets/icon.svg" width="64" height="64" alt="">

# screenshot-gif

A macOS menu bar app that records an area of the screen and copies it to the clipboard, ready to paste into an agent chat.

Agents see an animated GIF as one still frame. So by default the app copies a **PDF frame sheet**: the frames where the screen changed, in numbered, timestamped grids. It can copy an MP4 instead.

## Use

1. Press ⇧⌘Z and drag over an area.
2. A 3 second countdown runs, then recording starts. A red border marks the area.
3. Press ⇧⌘Z again to stop. The PDF (or MP4) is on the clipboard.

Esc cancels at any point and nothing is copied. The menu bar icon has "Copy Last Capture as PDF / MP4" and Settings.

## Build

```
./scripts/build-app.sh --install
```

This builds `Screenshot GIF.app` and copies it to `~/Applications`. The first launch asks for Screen Recording permission.

The build is ad hoc signed, so macOS asks for the permission again after each rebuild. To avoid that, set `SIGN_IDENTITY` to a code signing identity from your keychain.

Check frame picking and the PDF layout without recording:

```
.build/release/ScreenshotGif --pdf-from-gif in.gif out.pdf [maxFrames]
```

See [DESIGN.md](DESIGN.md) for the reasoning behind the design.
