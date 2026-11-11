# Folzio User Guide

English | [日本語](usage.ja.md) · [Back to README](../README.md)

This guide covers controls and detailed behavior.
For a first look, see the [README](../README.md).

## Contents

- [Interface language](#interface-language)
- [Checking the version](#checking-the-version)
- [Folders and favorites](#folders-and-favorites)
- [File list and layouts](#file-list-and-layouts)
- [Image and video preview](#image-and-video-preview)
- [Slideshow](#slideshow)
- [Organizing files](#organizing-files)
- [Browsing zip archives](#browsing-zip-archives)
- [Searching by name](#searching-by-name)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Where settings are stored](#where-settings-are-stored)
- [When files are not visible](#when-files-are-not-visible)

## Interface Language

- The interface supports English and Japanese. The default is English.
- To change it, open Settings (⌘,) and choose Language.
  The change takes effect immediately and is restored on the next launch.
- Text provided by macOS follows the system settings.

## Checking the Version

- Choose Folzio → "About Folzio" (Folzio について).
  It shows the app icon, the version, and a link to the GitHub repository.
- Close it with ⌘W. It also closes when the main window closes.

## Folders and Favorites

### Directory Tree

- The tree shows your home folder and mounted volumes.
- Double-click a folder row to expand or collapse it.
- The disclosure triangle appears only on folders that have subfolders
  (hidden folders and packages do not count).
- Select several folders with ⌘-click, Shift-click, or Shift+↑↓.
  - The file list shows the folder you clicked (or moved to with the keyboard) last.
  - Drag the selected folders to move them together. Hold Option to copy.
- Move folders to the Trash with ⌘Delete or "Move to Trash" (ゴミ箱に入れる) in the context menu.
  - Folders go with their contents. A multiple selection is moved in one operation.
  - A confirmation always appears, regardless of Settings. It shows each folder's name and absolute path.
  - Not available when the selection includes home, the top level of a volume, or a favorite.
    Also not available when it includes both a folder and a folder inside it.
  - If you move the folder being shown to the Trash, the file list shows its parent.

### Favorites

- "Favorites" (お気に入り) at the top of the tree holds frequently used folders.
- To add a folder, right-click it in the tree and choose "Add to Favorites" (お気に入りに追加), or press ⌃⌘T.
- To remove an entry, right-click it and choose "Remove from Favorites" (お気に入りから削除), or press ⌘Delete.
  - A confirmation shows the display name and the absolute path.
  - The actual folder is not changed.
  - On a regular folder, ⌘Delete means "Move to Trash" instead.
- To rename an entry, press Return, right-click → "Rename" (名前を変更), or choose Edit → "Rename".
  - The name is edited in place. Return commits, and Esc cancels.
  - Clearing the name restores the original folder name.
  - There is no confirmation, and the actual folder is not renamed.
- ⇧⌘F jumps to the Favorites heading.
- Favorites are saved and restored on the next launch.
  Folders that cannot be found stay in the list, dimmed.

### Folders in the File List

- The file list also shows subfolders (excluding hidden folders and packages).
- Double-click a folder row or press ⌘↓ to open it.
- Press ⌘↑ or use the `..` row at the top to return to the parent.
  - There is no `..` row at the top level of home or a volume, and ⌘↑ does nothing there.
- When you move between folders in the list, the tree selection follows.
  Keyboard focus stays on the file list.
- Folders can be copied, renamed, moved, and moved to the Trash just like files.

### Changes Outside the App

- Files added, deleted, or renamed outside the app are reflected in the list (via FSEvents).

## File List and Layouts

### View Modes and Columns

- Switch between list view and thumbnail view. You can change the thumbnail size.
- Click a column header to sort.
  - When sorting by name, folders always come before files, in both ascending and descending order.
  - Zip files count as files.
- Right-click the column header to show or hide the Date Created, Kind, Size, and Date Modified columns.

### Toolbar

- The toolbar has the view-mode buttons and the thumbnail-size slider.
- It is hidden by default. Toggle it with ⇧⌘T. Its state is restored on the next launch.
- To customize it, right-click the toolbar and choose "Customize Toolbar…".
  - Drag button groups to rearrange them. A group such as Back/Forward or Thumbnails/List moves as one unit.
  - You can also remove and re-add groups, add spaces, and change the display mode.
  - The order and display mode are restored on the next launch.

### Pane Layouts

- There are three layouts: three panes, file list only, and preview only.
  The tree cannot be hidden on its own.
- Switch layouts in any of these ways. All of them share the same state.
  - The "Show File List Only" and "Show Preview Only" buttons at the left of the default toolbar
  - ⌃⌘2 / ⌃⌘3
  - The matching items in the View menu (表示)
- The menu and shortcuts work even while the toolbar is hidden.
- While a pane is hidden:
  - In the preview-only layout, the arrow keys move the selection in the hidden file list
    (up/down/left/right in thumbnail view, up/down in list view).
  - When the list has no media, the preview shows "No media file to display" (表示するメディアファイルがありません).
  - Focusing a hidden pane, favorites, search, and similar actions are disabled.
  - Full screen is available from either layout and returns to it on exit.
- For videos, `<` / `>` skip back / forward 5 seconds. This works in the three-pane layout too.
- The layout is not saved. Every launch starts in the three-pane layout.

### Kind Filter

- The kind filter shows only images or only videos.
- Toggle it with the "Show Images Only" (画像のみ表示) and "Show Videos Only" (動画のみ表示) toolbar buttons,
  the View menu, or ⇧⌘I / ⇧⌘M.
- With only one of them on, only that kind is shown. With both on or both off, everything is shown.
- The state is not saved. Each launch starts with both off.
  While the app is running, the state is kept when you change folders.

## Image and Video Preview

### Display

- Shows JPEG / PNG / GIF / WebP / MP4 / MOV. Hidden files and unsupported formats are not listed.
- Images fit the pane with their aspect ratio kept.
  - Images smaller than the pane are enlarged as far as they fit.
  - The same applies in full screen.
- Animated GIFs and animated WebP images play using OS-standard APIs.
  When playback is not supported, the first frame is shown.
- Videos support playback, looping, and an autoplay setting.
  Space plays or pauses while the preview's video has the focus.

### Quick Look and Default App

- Press Space in the file list to Quick Look the selected media.
  - It zooms from the row or thumbnail. Press Space again to close it.
  - With several items selected, it shows them together.
  - While it is open, the arrow keys move the selection.
  - A playing preview video is paused while it is open.
  - Not available while renaming, in full screen, during a slideshow, or inside a zip.
- Double-click a media row or thumbnail to open it in its default app.
  Inside a zip, this does nothing.
- Select one media file or zip file, then choose "Open With" from its context menu to open it in an associated app.
  The same command is available from the File menu.
  The default app appears first, followed by other apps, with each app's icon.
  It is unavailable for multiple selections, folders, and items inside a zip.

### Zoom

- Zoom the preview image with any of these:
  - The three magnifier buttons in the toolbar:
    "Zoom In" (拡大), "Zoom to Fit" (表示領域に合わせる), and "Zoom Out" (縮小)
  - The View menu
  - ⌘+ / ⌘- / ⌘0 (⌘= also zooms in)
- The fit size counts as 100%. The zoom ranges from 25% to 800% in 25% steps.
- Images zoom around their center, and parts that overflow are not shown.
  There is no scrolling, panning, pinching, or zoom-level readout.
- Available in the three-pane layout, the preview-only layout, and full screen.
- Disabled for videos, an empty preview, images that cannot be displayed, and the file-list-only layout.
- The zoom resets to 100% when you switch to another image (including slideshow auto-advance)
  or move through history.
- Full screen and resizing the window or panes keep the zoom level.
- The zoom level is neither saved nor recorded in history.
- VoiceOver reads the current zoom level as the value.

### Full Screen

- Double-click an image or video (including the margins around it), or press ⌃⌘F.
- Press Esc to return.
- In full screen, double-clicking anywhere returns to the previous layout.
- Double-clicking the video playback controls or the image scroll bars does not toggle full screen.

## Slideshow

### Starting and Controls

- Start with ⇧⌘S, View → "Start Slideshow" (スライドショーを開始), or the play button in the toolbar.
  - During a slideshow, the play button in the toolbar appears pressed. Click it again to end the slideshow.
- The slideshow advances through the media in display order at the configured interval.
  - With repeat on, it wraps from the last item back to the first.
  - With repeat off, it ends one interval after the last item is shown.
  - Videos keep playing.
  - With only one item, it keeps showing that item and only restarts the timer.
    With repeat off, it ends after the interval.
- Starting switches to the preview-only layout.
  Ending restores the previous panes, focus, and widths.
- During a slideshow:
  - The arrow keys move through the hidden list and restart the timer.
  - Esc or the play button in the toolbar ends the slideshow.
  - `/` plays or pauses a video, and `<` / `>` seek 5 seconds. These do not change the timer.

### Slideshow Settings

- In the Settings window (⌘,), under "Slideshow" (スライドショー), you can change:
  - The interval: an integer from 1 to 3600 seconds (default 3)
  - "Repeat from the beginning after the last item" (最後まで表示したら先頭から繰り返す), default on
  - The transition effect: None / Crossfade / Slide / Zoom (default None)
- Committed changes take effect from the next auto-advance and are restored after a relaunch.
- Repeat is independent of video looping.

### Transition Effects

- Effects last about 0.5 seconds and apply only to auto-advance.
- They do not apply to the arrow keys, starting, ending, or selection changes outside the slideshow.
- While macOS "Reduce motion" is on, "Slide" and "Zoom" are shown as "Crossfade".
  The saved value is not changed.

### Limits and History

- Pane switching and history navigation are disabled during a slideshow.
- The slideshow ends automatically in these cases:
  - The browsed location is replaced.
  - There are no items.
  - The window is closed.
- The selection and preview changes made when it starts are not recorded in history.
- Only changes to the view mode, size, filter, and sort made while it runs are recorded, as normal view state.

## Organizing Files

### File Operations

- Copy, move, duplicate, rename, move to Trash, drag and drop, and clipboard operations are available.
  Folders include their contents.
- On a name conflict, choose "Replace", "Keep Both", or "Stop".
- A confirmation dialog appears before operations. You can skip it in Settings.

### Drag and Drop

- Drag a tree folder, or files and folders selected in either list view,
  onto a folder in the tree or the list (including search results) to move them.
- Drop on the file list's background, or on a file that is not a folder, to move items into the displayed folder.
  - While search results or the contents of a zip file are shown, only folders accept drops.
- Hold ⌥ when dropping to copy instead.
- Available favorites can be destinations.
- These are rejected:
  - A selection that contains both a folder and an item inside it
  - A move to the same parent
  - A transfer into the source folder or its descendants
- A name conflict shows a dialog regardless of the settings.
- When copying onto the source itself, choose Keep Both or Stop. Replace is unavailable.

### Drag and Drop with Other Apps

- Drag items from Folzio to a folder in Finder or to an upload field in a web browser.
  - Finder decides whether to move or copy: on the same volume it moves, and on another volume it copies. Hold ⌥ to copy or ⌘ to move.
  - To move a tree folder with ⌘, start dragging first and then press ⌘.
  - Folzio shows no confirmation. To undo, use Undo in Finder.
  - Dragging to the Trash in the Dock is not supported. Use ⌘Delete to move items to the Trash.
- Drop items from Finder on a folder in Folzio or on the file list's background.
  - The same rules as in Finder decide whether to move or copy: when every item is on the same volume it moves,
    and otherwise it copies. Hold ⌥ to copy or ⌘ to move.
  - The confirmation and conflict dialogs appear as for copies and moves inside Folzio.
- Web images can be saved as described below. Links or text alone are not accepted.

### Saving Images from a Browser

- Drag an image from Safari or Chrome onto a folder in the tree, an available favorite,
  or a folder in list view, thumbnail view, or search results. Drop on the background of a regular folder's
  file list to save there. Images are copied; modifier keys can prevent a drop if the browser does not allow copying.
- In the browser, choose “Copy Image”, then press ⌘V or choose “Paste” in Folzio's file list to save in the displayed folder.
  In the tree, select one regular folder and press ⌘V, or right-click it and choose “Paste Here”.
  Image data is saved as PNG, using the image URL's name when available, or a name such as `Image 2026-11-10 18.00.00.png`.
  When converting data with several frames or pages, only the first is saved.
- If the clipboard contains files, those files are pasted instead of an accompanying image.
  “Move Item Here” (⌥⌘V) is unavailable for image data alone. Pasting an image is unavailable inside a zip,
  in the search-results list, or on a favorite. During renaming, ⌘V belongs to the text editor.
- Drag photos or MOV/MP4 videos from Photos to save the exported files. Photos may export an HEIC photo as JPEG.
  Copying a photo in Photos and pressing ⌘V uses the file it provides; the original format is not guaranteed.
- If reception takes longer than two seconds, a panel shows progress. Use its Cancel button to cancel one reception,
  or ⌘. to cancel the most recently started one. During renaming or while a sheet or dialog is open, ⌘. cancels that edit
  or dialog and leaves reception running. Cancelling reception saves nothing to the destination;
  temporary files are removed after the source finishes exporting or the reception limits are reached.
- Saving uses the normal copy-confirmation setting. A name conflict always offers Replace, Keep Both, or Stop.
- Each image is limited to 256 MB, and each exported video to 4 GB. Converting image data to PNG is limited to
  100 megapixels in the first frame. Reception times out after 60 seconds for images, or ten minutes for video.
  Images that Folzio cannot display can still be saved when their format is supported for import;
  SVG, EPS, PostScript, PDF, and non-image documents are not imported as images.

### New Folders

- Press ⇧⌘N, choose File → "New Folder" (新規フォルダ),
  or use the context menu of a tree folder or the file list's background.
- A folder named "untitled folder" is created, and you name it in place. There is no confirmation.
- Where the folder is created:
  - In the file list: inside the displayed folder
  - In the tree: inside the selected or right-clicked folder
  - On a favorite: inside the registered folder
- Not available inside a zip, in search results, on the "Favorites" heading, or for a missing favorite.

### Copying the Path

- "Copy as Pathname" (パス名をコピー) copies the absolute path of the selected item as text.
  Use ⌥⌘C, the Edit menu, or the context menu.
- It works on one file, folder, or zip file in the list,
  or on a folder in the tree (including home, volume roots, and favorites).
- Not available for several selected rows, the `..` row, items inside a zip, or the "Favorites" heading.

## Browsing zip Archives

### Inside a zip

- Double-click a zip row or press ⌘↓ to show its contents.
- Press ⌘↑ or use the `..` row at the top to go back.
  At the top level of a zip, this returns to the list of the folder that contains it.
- Zip files do not appear in the tree.
- You can walk the directories inside a zip and preview its images and videos.
- The contents of a zip are read-only. Copy, rename, move to Trash, and other operations are not available.
  The zip file itself can be handled like any other file.
- Japanese file names inside zip files are displayed by auto-detecting the character encoding
  (UTF-8 / Shift_JIS, etc.) for each name.
- Videos inside zip files play without being extracted to a temporary file.
  They are read directly from the zip.

### Showing or Hiding zip Files

- Toggle with the "Show Zip Files" (zipファイルを表示) toolbar button, View → "Show Zip Files", or ⌃⌘Z.
- Zip files are hidden by default. The setting is saved and restored on relaunch.
- The button sits to the right of the kind filter and to the left of the view-mode buttons.
- While it is off, zip file rows are excluded from the list, selection, file operations,
  and full-screen navigation.
- It is independent of the kind filter. Only rows that meet both conditions are shown.
- Toggling it while viewing the inside of a zip does not change the list inside.

## Searching by Name

### Starting a Search

- Press ⌘F or choose File → "Find…" (検索…).
- A modal asks for a "Keyword" and "Search In".
  - The start folder defaults to the absolute path of the folder shown in the file list.
  - The keyword is pre-filled, fully selected, with the previous search from the same session.
  - The start folder must be a path starting with `/` or `~`.
  - If the path does not exist, is not a folder (including zip files), or cannot be read,
    the modal shows the reason.

### Choosing the Start Folder

- "Choose…" (選択…) next to the start folder opens the standard macOS folder picker.
- Choosing one folder and pressing "Choose" changes only the start folder field.
  The search does not start until you press "Search".
- Cancelling or a validation failure keeps the previous input and the reason, so you can choose again.
- In the standard panel:
  - You cannot choose files, zip files, or packages as folders.
  - There is no multiple selection or New Folder.
  - Hidden items can be shown with ⌘⇧. as usual, and hidden folders can be chosen.
- The existing validation rules for typed paths are unchanged.
- Keyboard:
  - Tab moves keyword → start folder → Choose… → Cancel → Search.
  - Space opens "Choose…".
  - Return, Esc, and navigation inside the standard panel behave as usual in macOS.
    Return and Esc there affect only the panel.
  - Closing the panel returns focus to "Choose…".
- Trailing spaces in a folder name chosen in the GUI are kept as long as you do not edit the field.
  If you edit the field directly, leading and trailing spaces are trimmed as before.

### Matching Rules

- Keywords containing `*` (zero or more characters) or `?` (one character) must match the whole name.
- Other keywords match any part of the name, including the extension.
- Differences in case and in composed/decomposed dakuten (NFC / NFD) are ignored.
- Full-width/half-width and hiragana/katakana are distinguished.
- The search covers supported media files and folders at all levels below the start folder.
- Folder names are also matched against the whole name.
  Names containing "." (`2024.10_trip`, `photos.jpg`) are not treated as having an extension.
- These are excluded:
  - Hidden files and hidden folders
  - Package contents
  - Symbolic links to folders (the link itself and its contents). Symbolic links to files are included.
  - Zip contents
  - The start folder itself
- If "Show Zip Files" (zipファイルを表示) is on when the search starts, zip file names are matched too.
  - Their contents are not searched.
  - Toggling the setting during a search applies from the next search.

### Search Results

- Results appear in the file list as a single list that mixes files and folders.
  - They are added in the order they are found and sorted by the current sort.
  - When sorting by name, folders are grouped first.
  - You can keep working while it searches.
- List view gets a "Location" (場所) column, the folder relative to the start folder.
  It can also be used for sorting.
- Thumbnail view shows the location as a tooltip.
- The search bar above the list shows:
  - The total number of files, folders, and zip files
  - "Searching…" (検索中…) while searching
  - "No matching items" (該当する項目はありません) when nothing matches
- Folder rows work like regular folder rows.
  - Open one with a double-click, ⌘↓, or right-click → "Show Contents" (中を表示).
  - Opening one closes the search results and shows that folder's list.
  - ⌘[ (Back) returns to the folder shown before the search.
  - Selecting a folder row clears the preview.
- Matching zip files appear as rows like in a regular list.
  - Double-click or ⌘↓ opens the top level of the zip.
  - They can be copied, renamed, moved, or moved to the Trash.

### Working with Results

- Preview, copy, duplicate, rename, move to Trash, and move all work on search results.
- Paste, move-paste, and ⌘↑ do not.
- Rows that are moved to the Trash, moved, or deleted outside the app are removed,
  along with the results inside them.
- Renamed rows stay under their new name.
  - The results inside them move to the new location.
  - Newly appearing files and folders are not added.
  - For a renamed folder row, whether the results inside it are carried over or enumerated again
    depends on whether it has already been matched.
- If you move an ancestor of a result folder (to the Trash or elsewhere) from the search results,
  the results stay shown. The rows and the results inside them are removed.
- If the folder shown before the search no longer exists when you close the results,
  "Folder not found" (フォルダが見つかりません) is shown.
- Moving an ancestor to the Trash from the tree goes to its parent as before.

### Closing the Results

- Select a folder in the tree (including clicking the already-selected row), or press Esc in the file list.
- Closing the results stops a search in progress.
- Search conditions, results, and sorting by "Location" are not saved.

## Keyboard Shortcuts

### Changing Shortcuts

- The keys in this guide are the defaults.
- You can change the shortcut of any menu command in Settings (⌘,) → Shortcuts (ショートカット).
  Press Record on its row, then press the new keys. Include ⌘, ⌃, or ⌥.
- These are refused with a reason, so two commands never share a key:
  - A combination that another command uses
  - A fixed key such as the arrow keys, Space, Return, Esc, or Tab
  - An app or system key such as ⌘Q or ⌘W
- Clear removes a command's shortcut. The command then shows Not Set and has no key.
- To swap the keys of two commands without hunting for a free one:
  1. Clear the first command.
  2. Give the second command the first one's old keys.
  3. Give the first command the second one's old keys.
- Reset returns one command to its default. Reset All returns every command.
- The menus, the toolbar tooltips, and the shortcut reference (⌘/) show your current keys.
- Control-Tab switches between the General and Shortcuts tabs.

### Window and Layout

| Action | Default shortcut |
|--------|----------|
| Settings | ⌘, |
| Quit | ⌘Q |
| Focus the tree / list / preview | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| File list only / preview only (the same key returns to three panes) | ⌃⌘2 / ⌃⌘3, View menu, toolbar |
| Show / hide the toolbar | ⇧⌘T, View menu |
| Full-screen preview / return | ⌃⌘F, double-click the image or video, Esc |

### Slideshow and Video

| Action | Default shortcut |
|--------|----------|
| Start / end a slideshow | ⇧⌘S (View menu, toolbar) / Esc (toolbar) |
| Move through the hidden list during a slideshow (restarts the timer) | Arrow keys |
| Play / pause a video or seek 5 seconds during a slideshow | `/`, `<` / `>` |
| Skip a video back / forward 5 seconds (not while typing) | `<` / `>` |
| Play / pause a video (with the preview's video focused) | Space |

### Folders and Favorites

| Action | Default shortcut |
|--------|----------|
| Expand / collapse a folder in the tree | → / ←, double-click a folder row |
| Select several folders in the tree | ⌘-click, Shift-click, Shift+↑ / ↓ |
| Move tree folders to the Trash | ⌘Delete, "Move to Trash" in the context menu |
| Add to Favorites | ⌃⌘T, tree context menu |
| Rename a favorite | Return, "Rename" in the context menu, Edit menu → "Rename" |
| Remove from Favorites | ⌘Delete, the favorite's context menu |
| Jump to the "Favorites" heading | ⇧⌘F |
| Show the contents of a folder, a zip file, or a directory inside a zip | Double-click, ⌘↓, "Show Contents" in the context menu |
| Go up one level | ⌘↑, double-click the `..` row, "Enclosing Folder" (上の階層へ) in the context menu |

### File List and Preview

| Action | Default shortcut |
|--------|----------|
| Thumbnail view / list view | ⌘1 / ⌘2 |
| Larger / smaller thumbnails | ⌃⌘. / ⌃⌘,, View menu |
| Sort | Click a column header, View menu → Sort By |
| Images only / videos only | ⇧⌘I / ⇧⌘M, View menu, toolbar |
| Show / hide zip files | ⌃⌘Z, View menu → "Show Zip Files", toolbar |
| Move the selection in the hidden file list (preview only) | Arrow keys |
| Quick Look the selected media | Space in the file list |
| Open media in its default app | Double-click a media row or thumbnail |
| Open one media or zip file in an associated app | Ctrl+F2 (or Fn+Ctrl+F2) → File → Open With |
| Zoom the preview image in / out / fit to view | ⌘+ (⌘= also works) / ⌘− / ⌘0, View menu, toolbar |

### Files

| Action | Default shortcut |
|--------|----------|
| Copy / paste / move-paste | ⌘C / ⌘V / ⌥⌘V |
| Duplicate | ⌘D |
| New folder | ⇧⌘N, File menu → "New Folder", context menu |
| Rename (in place) | Return |
| Move to Trash | ⌘Delete |
| Open the selected item | ⌘O |
| Show in Finder | Context menu / File menu |
| Copy as Pathname | ⌥⌘C, Edit menu, context menu |

### Search

| Action | Default shortcut |
|--------|----------|
| Search by name (file and folder names) | ⌘F, File menu → "Find…" |
| Choose the search start folder | "Choose…" in the search sheet (Tab to move to it, Space to open it) |
| Open a folder row in the search results | Double-click, ⌘↓, "Show Contents" in the context menu |
| Close the search results | Select a folder in the tree, Esc in the file list |

## Where Settings Are Stored

- Settings are stored in `UserDefaults`.
- Shortcut changes are stored in `shortcuts.overrides`, only for the commands that differ from the default.
- The `.app` and `swift run` use different domains.

```bash
# Reset the settings of the .app
defaults delete local.folzio.Folzio

# Reset the settings of swift run
defaults delete FolzioApp
```

## When Files Are Not Visible

- In System Settings → Privacy & Security → Files and Folders, allow access for Folzio.
- If you launch from Terminal, check the permissions for Terminal instead.
