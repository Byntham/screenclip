# Design

A macOS menu bar app that records a selected area of the screen and puts the result on the clipboard, as easily as ⇧⌘4 takes a screenshot. The main use is pasting into T3 Code so an agent can see what happened.

## Why not a GIF

Agents read an animated GIF as one still frame. A test on a 229 frame GIF showed only frame 1. Video-capable models sample about 1 frame per second, which misses fast events. Claude can't watch video at all.

So the main output is a **frame sheet PDF**: frames laid out in grids, one grid per page, each frame labeled with its number and timestamp. An MP4 is the second output, for people and for models that accept video.

## Flow

1. Press the hotkey (default ⇧⌘Z, rebindable).
2. Drag to select an area.
3. On mouse release, a 3 second countdown runs, then recording starts.
4. Press the hotkey again to stop. The output goes to the clipboard.
5. Esc at any point cancels. Nothing is copied or kept.

Recording stops by itself at the max length.

## Output

- Clipboard only. No files are kept. Temp files that the paste needs are deleted later.
- One paste gives **one item** for the frames, not one file per frame.
- A setting picks what gets copied: frame sheet PDF or MP4. A paste can't carry two files, so "both" isn't an option. The menu can copy the last capture in the other format.
- The clipboard holds file references. T3 Code copies pasted files into its own attachments folder, so the app deletes its temp files on the next capture and on quit.

## Frame sheet rules

- Frames must stay sharp enough to read text. Agents shrink large images (roughly 1500 to 2500 px on the long edge), so each page stays near 2000 px wide.
- Frames are drawn at the highest scale that fits, never below 1x (point size). Small capture areas get 2x Retina detail and up to 6 frames per page. Large areas get fewer frames per page, down to 1.
- Pick frames where the screen changed. Skip duplicates.
- If more frames changed than the cap allows, spread the cap along the timeline by how much changed (70%) and by elapsed time (30%). Busy stretches get more frames, and a long pause still gets one. An earlier version kept only the largest changes and missed the key moment in a test clip.
- Each frame gets a number and a timestamp.

## Settings

| Setting | Options | Default |
|---|---|---|
| Hotkey | any | ⇧⌘Z |
| Frame rate | 10, 15, 30, 60 | 15 |
| Max length | 10, 15, 30, 60, 120 s | 30 |
| Output | PDF, MP4 | PDF |
| Max frames in PDF | 12, 24, 36, 48, 72 | 48 |
| Show cursor | on, off | on |
| Launch at login | on, off | off |

## Platform

Native Swift for macOS. Windows may come later as a separate app with the same design.

## Paste test results

From `experiments/paste-test`, pasting into T3 Code with Claude as the agent:

| Pasted | Result |
|---|---|
| PNG as image data | Agent sees the image |
| PNG as a file | Agent sees the image |
| PDF as a file | Agent sees every page inline, all frames readable |
| MP4 as a file | Agent gets only a file path and can't watch it |
| PNG + MP4 together | Nothing pastes |
