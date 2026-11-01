# Design

A macOS menu bar app that records a selected area of the screen and puts the result on the clipboard, as easily as ⇧⌘4 takes a screenshot. The main use is pasting into T3 Code so an agent can see what happened.

## Why not a GIF

Agents read an animated GIF as one still frame. A test on a 229 frame GIF showed only frame 1. Video-capable models sample about 1 frame per second, which misses fast events. Claude can't watch video at all.

So the main output is a **frame sheet**: frames laid out in a grid, each labeled with its number and timestamp. An MP4 is the second output, for people and for models that accept video.

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
- A setting picks what gets copied: frame sheet, MP4, or both.

## Frame sheet rules

- Frames must stay sharp enough to read text. Agents shrink large images (roughly 1500 to 2500 px on the long edge), so the sheet must respect that limit.
- Pick frames where the screen changed. Skip duplicates.
- Each frame gets a number and a timestamp.

## Settings

| Setting | Options | Default |
|---|---|---|
| Hotkey | any | ⇧⌘Z |
| Frame rate | 10, 15, 30, 60 | 15 |
| Max length | seconds | 30 |
| Output | sheet, MP4, both | both |
| Show cursor | on, off | on |
| Launch at login | on, off | off |

## Platform

Native Swift for macOS. Windows may come later as a separate app with the same design.

## Open questions

- What T3 Code accepts on paste: one PNG, a PDF, an MP4, several files at once. See `experiments/paste-test`.
