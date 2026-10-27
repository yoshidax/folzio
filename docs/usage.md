# Folzio User Guide

English | [日本語](usage.ja.md) · [Back to README](../README.md)

This guide covers controls and detailed behavior. For a first look, see the [README](../README.md).

## Contents

- [Folders and favorites](#folders-and-favorites)
- [File list and layouts](#file-list-and-layouts)
- [Image and video preview](#image-and-video-preview)
- [Slideshow](#slideshow)
- [Organizing files](#organizing-files)
- [Browsing zip archives](#browsing-zip-archives)
- [Searching by name](#searching-by-name)
- [Keyboard shortcuts](#keyboard-shortcuts)

## Interface Language

The interface supports English and Japanese and defaults to English. Open Settings (⌘,) and choose Language to change it;
the choice takes effect immediately and is saved for the next launch. macOS-provided interface text follows system settings.

## Folders and Favorites

- Folder navigation from the directory tree (home and mounted volumes). Double-click a folder row to expand or collapse it.
  The disclosure triangle appears only on folders that have subfolders (excluding hidden folders and packages)

- Register frequently used folders under "Favorites" (お気に入り) at the top of the tree (right-click in the tree → "Add to Favorites" (お気に入りに追加), or ⌃⌘T). Remove an entry with right-click → "Remove from Favorites" (お気に入りから削除) or ⌘Delete after a confirmation (on a regular folder, ⌘Delete means "Move to Trash" instead); the actual folder is not changed. The confirmation shows the display name and the absolute path.
  Rename an entry with Return, right-click → "Rename" (名前を変更), or Edit → "Rename" (edited in place; Return commits, Esc cancels, and clearing the name restores the original folder name. There is no confirmation dialog, and the actual folder is not renamed). ⇧⌘F jumps to the heading. Favorites are saved and restored on the next launch, and folders that cannot be found stay in the list, dimmed

- The file list also shows subfolders (excluding hidden folders and packages). Double-click a folder row or press ⌘↓ to open that folder's list,
  and press ⌘↑ or use the `..` row at the top to return to the parent (there is no `..` row at the top level of home or a volume). Navigating within the list keeps the tree selection
  in sync with that folder (keyboard focus stays on the file list). Folders can be copied, renamed, moved to the Trash, and moved just like files

- Files added, deleted, or renamed outside the app are reflected in the list via FSEvents

## File List and Layouts

- Switching between list and thumbnail views, adjustable thumbnail size, and sorting by column header

- A toolbar with view-mode buttons and a thumbnail-size slider (hidden by default. Toggle it with ⇧⌘T; its state is restored on the next launch)

- Pane layout switching (three panes / file list only / preview only). Switch with the "Show File List Only" and "Show Preview Only" buttons at the left end of the toolbar,
  ⌃⌘2 / ⌃⌘3, or the matching items in the View menu (表示). All three share the same state (the menu and shortcuts work even while the toolbar is hidden).
  The tree cannot be hidden on its own, so the layouts are three panes, file list only, and preview only
  - In the preview-only layout, the arrow keys move the selection in the hidden file list (up/down/left/right in thumbnail view, up/down in list view). For videos, `<` / `>` skip back / forward 5 seconds
  - When the list has no media, the preview shows "No media file to display" (表示するメディアファイルがありません)
  - Focusing a hidden pane, favorites, search, and similar actions are disabled
  - Full screen is available from either layout and returns to it on exit
  - The layout is not saved; every launch starts in the three-pane layout

- A kind filter that shows only images or only videos (the "Show Images Only" (画像のみ表示) and "Show Videos Only" (動画のみ表示) toolbar buttons, the View menu, ⇧⌘I / ⇧⌘M. With only one of them on, only that kind is shown; with both on or both off, everything is shown. The state is not saved: each launch starts with both off, and the state persists across folder changes while the app is running)

## Image and Video Preview

- Displays JPEG / PNG / GIF / WebP / MP4 / MOV (hidden files and unsupported formats are not listed)

- Aspect-preserving fit display (images smaller than the pane are enlarged as far as they fit without overflowing. The same applies in full screen)

- Zooming the preview image (the three magnifier buttons in the toolbar, "Zoom In" (拡大), "Zoom to Fit" (表示領域に合わせる), and "Zoom Out" (縮小); the View menu; or ⌘+ / ⌘- / ⌘0.
  ⌘= also zooms in). The fit size counts as 100%, and the zoom ranges from 25% to 800% in 25% steps. Images zoom around their center,
  and parts that overflow are not shown (there is no scrolling, panning, pinching, or zoom-level readout)
  - Available in the three-pane layout, the preview-only layout, and full screen. Disabled for videos, an empty preview, images that cannot be displayed, and the file-list-only layout
  - Switching to another image (including slideshow auto-advance) or moving through history resets the zoom to 100%. Full screen and resizing the window or panes keep the zoom level
  - The zoom level is neither saved nor recorded in history. VoiceOver reads the current zoom level as the value

- Animated GIF playback and animated WebP playback (using OS-standard APIs; falls back to the first frame when unsupported)

- Video playback, looping, an autoplay setting, and play/pause with the Space key

- Full-screen preview (double-click or ⌃⌘F; Esc to return)

## Slideshow

- Slideshow (⇧⌘S, View → "Start Slideshow" (スライドショーを開始), or the play button in the toolbar). Advances through the media
  in display order at the configured interval. With repeat on, it wraps from the last item back to the first; with repeat off, it ends one interval after the last item is shown.
  Videos keep playing. With only one item, it keeps showing that item and only restarts the timer (with repeat off, it ends after the interval).
  Starting switches to the preview-only layout, and ending restores the previous panes, focus, and widths. The arrow keys move through the hidden list and restart the timer,
  and Esc ends the slideshow. `/` plays or pauses a video and `<` / `>` seek 5 seconds; these do not change the timer
  - In the Settings window (⌘,), under "Slideshow" (スライドショー), you can change the interval (an integer from 1 to 3600 seconds, default 3),
    "Repeat from the beginning after the last item" (最後まで表示したら先頭から繰り返す, default on), and the transition effect (None / Crossfade / Slide / Zoom, default None).
    Committed changes take effect from the next auto-advance and are restored after a relaunch. Repeat is independent of video looping
  - Transition effects (about 0.5 seconds) apply only to auto-advance, not to the arrow keys, starting, ending, or selection changes outside the slideshow.
    While macOS "Reduce motion" is on, "Slide" and "Zoom" are shown as "Crossfade" (the saved value is not changed)
  - Pane switching and history navigation are disabled during a slideshow. It ends automatically when the browsed location is replaced, when there are no items, or when the window is closed
  - The selection and preview changes made when it starts are not recorded in history; only changes to the view mode, size, filter, and sort made while it runs are recorded, as normal view state

## Organizing Files

- Copy / move / duplicate / rename / move to Trash / drag and drop / clipboard operations (folders include their contents)

- "Replace / Keep Both / Stop" choices on conflicts, and a confirmation dialog before operations (can be skipped in Settings)

## Browsing zip Archives

- Browsing inside zip files (double-click a zip row or press ⌘↓ to show its contents; press ⌘↑ or use the `..` row at the top to go back.
  Zip files do not appear in the tree). You can walk the directories inside a zip and preview its images and videos. The contents of a zip are read-only,
  so copy, rename, move to Trash, and other operations are not available (the zip file itself can be handled like any other file)

- Toggling the visibility of zip files (the "Show Zip Files" (zipファイルを表示) toolbar button, View → "Show Zip Files", ⌃⌘Z).
  Hidden by default. The button sits to the right of the kind filter and to the left of the view-mode buttons. The setting is saved and restored on relaunch
  - While it is off, zip file rows are excluded from the list, selection, file operations, and full-screen navigation. It is independent of the kind filter; only rows that meet both conditions are shown
  - Toggling it while viewing the inside of a zip does not change the list inside

- Japanese file names inside zip files are displayed by auto-detecting the character encoding (UTF-8 / Shift_JIS, etc.) for each name

- Videos inside zip files play without being extracted to a temporary file (they are read directly from the zip)

## Searching by Name

- Name search (⌘F or File → "Find…" (検索…)). A modal asks for a "Keyword" and "Search In".
  The start folder defaults to the absolute path of the folder shown in the file list, and the keyword is pre-filled, fully selected, with the previous search from the same session.
  The start folder must be a path starting with `/` or `~`. If it does not exist, is not a folder (including zip files), or cannot be read, the modal shows the reason
  - "Choose…" (選択…) next to the start folder opens the standard macOS folder picker. Choosing one folder and pressing "Choose" changes only the start folder field,
    and the search does not start until you press "Search". Cancelling or a validation failure keeps the previous input and the reason, so you can choose again
  - The standard panel does not let you choose files, zip files, or packages as folders, and offers no multiple selection or New Folder. Hidden items can be shown with
    ⌘⇧. as usual, and hidden folders can be chosen. The existing validation rules for typed paths are unchanged
  - Keyboard: Tab moves keyword → start folder → Choose… → Cancel → Search, and Space opens "Choose…".
    Return, Esc, and navigation inside the standard panel behave as usual in macOS, and closing the panel returns focus to "Choose…"
  - Trailing spaces in a folder name chosen in the GUI are kept as long as the start folder field is not edited. If you edit the field directly, leading and trailing spaces are trimmed as before
  - Keywords containing `*` (zero or more characters) or `?` (one character) must match the whole name; other keywords match any part of the name (including the extension)
  - Differences in case and in composed/decomposed dakuten (NFC / NFD) are ignored. Full-width/half-width and hiragana/katakana are distinguished
  - Searches all levels below the start folder for supported media files and folders. Folder names are also matched against the whole name, and names containing "."
    (`2024.10_trip`, `photos.jpg`) are not treated as having an extension. Hidden files, hidden folders, package contents,
    symbolic links to folders (the link itself and its contents), zip contents, and the start folder itself are excluded
    (symbolic links to files are included)
  - Results appear in the file list as a single list that mixes files and folders, added in the order they are found and sorted by the current sort. You can keep working while it searches.
    List view gets a "Location" (場所) column (the folder relative to the start folder), which can also be used for sorting. Thumbnail view shows the location as a tooltip.
    The search bar above the list shows the total number of files and folders, "Searching…" (検索中…) while searching, and "No matching items" (該当する項目はありません) when nothing matches
  - Folder rows are the same as regular folder rows and open with a double-click, ⌘↓, or right-click → "Show Contents" (中を表示). Opening one closes the search results and
    shows that folder's list, and ⌘[ (Back) returns to the folder shown before the search. Selecting a folder row clears the preview
  - Preview, copy, duplicate, rename, move to Trash, and move all work on search results. Paste, move-paste, and ⌘↑ do not.
    Rows that are moved to the Trash, moved, or deleted outside the app are removed from the list along with the results inside them. Renamed rows stay under their new name (the results inside them move to the new location,
    and newly appearing files and folders are not added). When a folder row is renamed, whether the results inside it are carried over or enumerated again depends on whether it has already been matched
  - Moving an ancestor of a result folder to the Trash, or moving it, from the search results keeps the search results shown (the rows and the results inside them are removed).
    If the folder shown before the search no longer exists when the search results are closed, "Folder not found" (フォルダが見つかりません) is shown. Moving an ancestor to the Trash from the tree goes to its parent as before
  - Selecting a folder in the tree (including clicking the already-selected row) or pressing Esc in the file list closes the search results (and stops a search in progress)
  - Search conditions, results, and sorting by "Location" are not saved

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Settings | ⌘, |
| Quit | ⌘Q |
| Focus the tree / list / preview | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| File list only / preview only (the same shortcut returns to three panes) | ⌃⌘2 / ⌃⌘3, View menu, toolbar |
| Start / end a slideshow | ⇧⌘S (View menu, toolbar) / Esc |
| Move through the hidden list during a slideshow (the timer also restarts at the configured interval) | Arrow keys (up/down/left/right in thumbnail view, up/down in list view. Esc ends) |
| Play/pause a video or seek 5 seconds during a slideshow | `/`, `<` / `>` |
| Move the selection in the hidden file list (preview only) | Arrow keys (up/down/left/right in thumbnail view, up/down in list view) |
| Skip a video back / forward 5 seconds (preview only) | `<` / `>` |
| Expand / collapse a folder in the tree | → / ←, double-click a folder row |
| Add to Favorites | ⌃⌘T, tree context menu |
| Rename a favorite (edited in place. Return commits, Esc cancels, clearing the name restores the original folder name. No confirmation. The actual folder is not renamed) | Return, "Rename" in the favorite's context menu, Edit menu → "Rename" |
| Remove from Favorites (with a confirmation that shows the display name and the absolute path. The actual folder is not changed) | ⌘Delete, the favorite's context menu |
| Move a folder in the tree to the Trash (with its contents. Asks for confirmation, which can be skipped in Settings. Not available for home or the top level of a volume. Trashing the folder being shown shows its parent) | ⌘Delete, "Move to Trash" in the tree folder's context menu |
| Jump to the "Favorites" heading | ⇧⌘F |
| Thumbnail view / list view | ⌘1 / ⌘2 |
| Larger / smaller thumbnails | ⌃⌘. / ⌃⌘,, View menu |
| Zoom the preview image in / out / fit to view (25% steps, 25%–800%) | ⌘+ (⌘= also works) / ⌘− / ⌘0, View menu, toolbar |
| Show / hide the toolbar | ⇧⌘T, View menu |
| Images only / videos only | ⇧⌘I / ⇧⌘M, View menu, toolbar |
| Show / hide zip files (hidden by default. Saved and restored on relaunch. While off, zip files are excluded from the list, selection, file operations, and full-screen navigation. Toggling while viewing the inside of a zip does not change the list inside) | ⌃⌘Z, View menu → "Show Zip Files", toolbar (right of the kind filter, left of the view-mode buttons) |
| Play / pause a video (from the list) | Space |
| Full-screen preview / return | ⌃⌘F, double-click the image, Esc |
| Copy / paste / move-paste | ⌘C / ⌘V / ⌥⌘V |
| Duplicate | ⌘D |
| Rename (in place) | Return |
| Move to Trash | ⌘Delete |
| Open the selected item | ⌘O |
| Show in Finder | Context menu / File menu |
| Show the contents of a folder, a zip file, or a directory inside a zip | Double-click, ⌘↓, "Show Contents" in the context menu |
| Go up one level (at the top of a zip, to the list of the folder containing it; does nothing at the top level of home or a volume) | ⌘↑, double-click the `..` row at the top, "Enclosing Folder" (上の階層へ) in the context menu |
| Sort | Click a column header, View menu → Sort By |
| Search by name (file and folder names) | ⌘F, File menu → "Find…" |
| Choose the search start folder | "Choose…" in the search sheet (move to it with Tab, open it with Space). Return and Esc in the standard panel affect only the panel |
| Close the search results | Select a folder in the tree (including clicking the selected row), Esc in the file list |
| Open a folder row in the search results | Double-click, ⌘↓, "Show Contents" in the context menu |

Inside the app, drag a tree folder or selected files and folders from either list view onto a folder in the tree or list (including search results) to move them; hold ⌥ when dropping to copy instead. Available favorites can be destinations. A selection containing both a folder and an item inside it is rejected, as are moves to the same parent and transfers into the source folder or its descendants.
A name conflict shows a dialog regardless of the settings. When copying onto the source itself, choose Keep Both or Stop; Replace is unavailable.

## Where Settings Are Stored

Settings are stored in `UserDefaults`. The `.app` and `swift run` use different domains.

```bash
# Reset the settings of the .app
defaults delete local.folzio.Folzio

# Reset the settings of swift run
defaults delete FolzioApp
```

## When Files Are Not Visible

In System Settings → Privacy & Security → Files and Folders, allow access for Folzio.
If you launch from Terminal, check the permissions for Terminal instead.
