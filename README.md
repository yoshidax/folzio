# Folzio

English | [日本語](README.ja.md)

**Browse and organize your images and videos, right in their folders.**

Folzio is a native macOS app that brings folder navigation, thumbnails, and previews together in one window.
Browse a folder of photos, animated images, and video clips, then organize files as you view them.

macOS 15 or later · Apple silicon only · English and Japanese · Works locally without network communication · [MIT License](LICENSE)

## Features

- **Keep the whole folder in view.** Navigate folders, scan thumbnails or a file list, and preview the selected item
  side by side in a three-pane layout. Save frequently used folders as favorites.
- **View images and videos together.** Browse photos, animated GIFs, WebP images, and videos in the same list,
  with video autoplay and looping available.
- **Organize while you browse.** Copy, move, duplicate, rename, and trash files and folders with familiar macOS
  shortcuts and drag and drop.
- **Look inside zip archives.** Browse folders and preview images and videos inside zip files.
  Archive contents are read-only; videos play directly from the archive without temporary extraction.
- **Find files across folders.** Search file and folder names, then preview and organize matching items
  without leaving the results.
- **Focus on your media.** Zoom images, switch to preview-only or full-screen viewing, or start a slideshow
  with adjustable timing and transitions.

## Download

The app is available from GitHub Releases. It requires macOS 15 or later on an Apple silicon Mac;
Intel Macs are not supported.

1. Open this repository's **Releases** page and download `Folzio-vX.Y.Z-macos-arm64.zip` from the desired release.
2. Unzip the file and move `Folzio.app` to Applications, then open it.
3. The app is not signed with a Developer ID or notarized by Apple. If macOS blocks it, and you trust the download,
   open System Settings → Privacy & Security and choose **Open Anyway**, then confirm. See
   [Apple's instructions](https://support.apple.com/en-us/102445).

To try it from source, see the [build and launch instructions](docs/development.md).
Xcode with the Swift 6 toolchain is required to build the app.

## Get Started

1. Launch Folzio and choose a folder in the tree on the left.
2. Select an image or video in the center to preview it on the right. Use the arrow keys to browse the list.
3. Switch between thumbnails and list view with ⌘1 / ⌘2. Drag files onto a folder to move them;
   hold ⌥ when dropping to copy instead.

To change the interface language, open Settings (⌘,) and choose Language. English is the default.
If a folder is not accessible, allow Folzio access in System Settings → Privacy & Security → Files and Folders.

## Useful Shortcuts

| Action | Shortcut |
|--------|----------|
| Thumbnail view / list view | ⌘1 / ⌘2 |
| Search file and folder names | ⌘F |
| Open a folder / go up one level | ⌘↓ / ⌘↑ |
| Zoom an image in / out / fit to view | ⌘+ / ⌘− / ⌘0 |
| Play / pause a video from the file list | Space |
| Enter / exit full screen | ⌃⌘F |
| Start / end a slideshow | ⇧⌘S / Esc |
| Show / hide zip files | ⌃⌘Z |

See the [user guide](docs/usage.md) for more shortcuts, settings, and detailed behavior.

## Supported Formats and Limits

- **Images:** JPEG, PNG, GIF, and WebP. Animated WebP playback depends on macOS support;
  when unsupported, the first frame is displayed.
- **Videos:** MP4 and MOV. Playback depends on the codecs supported by macOS.
- **zip archives:** Browse and preview supported media. Archive contents cannot be edited,
  and name searches do not look inside archives. Zip files are hidden by default; show them with ⌃⌘Z.

## Guides

- [User guide](docs/usage.md) — folder navigation, favorites, search, zoom, slideshows, and file operations.
- [Development and verification](docs/development.md) — source builds, automated tests, fixtures, and project structure.

## Project Policy

Folzio is a personal project developed and maintained by its author.
External contributions, including pull requests, bug reports, and feature requests, are not accepted.
Issues are reserved for the maintainer's own tracking.

You are welcome to use, modify, fork, and redistribute the project under the MIT License.

## License

[MIT License](LICENSE)
