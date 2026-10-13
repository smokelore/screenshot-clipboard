# Screenshot Clipboard

A small Mac menu bar app that copies every new screenshot to the clipboard the moment macOS saves it. You keep using the built-in screenshot tool (⌘⇧3, ⌘⇧4, ⌘⇧5), and each capture is both saved as a file and ready to paste.

## What it does

- **Screenshots** go on the clipboard as an image, as a file, and as a file path. Apps paste whichever they understand: the picture in chats and documents, the file in Finder, the path in Terminal.
- **Screen recordings** go on the clipboard as a file and a path.
- **Your save folder** is whatever macOS uses; change it in ⌘⇧5 → Options and the app follows.
- **Deleting** the capture you just copied clears the clipboard, unless you've copied something else since.

The menu bar icon flashes a checkmark after each copy. Drag the icon to drop your latest capture into any app or folder. Click it for the menu:

- **About:** version, author, and a link to this repository.
- **Pause / Resume:** stop copying until you resume. **For 1 Hour**, beside it, resumes by itself.
- **Copy Latest:** copy the most recent capture again.
- **Open Folder:** open the screenshot folder.
- **Open at Login:** start the app when you log in.
- **Quit**

## Setup

Requires a Mac with macOS 13 or later and Apple's command line tools (`xcode-select --install`).

```sh
git clone https://github.com/smokelore/screenshot-clipboard.git
cd screenshot-clipboard
./build.sh --install
```

This builds the app, puts it in `/Applications`, and starts it. It turns on Open at Login the first time it runs.

If macOS asks whether Screenshot Clipboard may access a folder, such as Documents, click **Allow**. The app needs it to read your screenshots.

Without a signing certificate, macOS asks again after every rebuild. To make it remember, create one once: in Keychain Access choose Keychain Access → Certificate Assistant → Create a Certificate, name it `Screenshot Clipboard Local Signing`, set Certificate Type to **Code Signing**, and rebuild. `build.sh` uses it when it's there.

If you use a menu bar manager such as Ice or Bartender, the icon may start hidden; move it into view there.

## Removing it

Untick **Open at Login**, choose **Quit**, then drag `/Applications/Screenshot Clipboard.app` to the Trash.
