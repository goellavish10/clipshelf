# ClipShelf

ClipShelf is a small, local-only macOS clipboard history app. It lives in the menu bar, records text, rich text, links, images, and Finder file references, and restores any entry to the system clipboard for the next normal `⌘V`.

## Requirements

- macOS 13 or newer
- Xcode 15 or newer (tested with Xcode 26.3)

## Run it

Build a normal local application bundle and open it:

```sh
make run
```

The app will appear as a clipboard icon in the menu bar. The built application is at `build/ClipShelf.app`; you can drag it into `/Applications` if you want to keep it there.

You can also open `Package.swift` in Xcode and run the `ClipShelf` executable target.

## Use it

1. Leave ClipShelf running in the menu bar.
2. Copy text, a link, an image, or Finder files normally.
3. Open the clipboard icon and choose a history entry.
4. Press `⌘V` in the destination app.

Right-click a history row to pin or delete it. Pinned entries are kept when clearing history.

## Local data

History is stored in:

```text
~/Library/Application Support/ClipShelf
```

ClipShelf keeps up to 200 unpinned entries and 300 MB of clipboard payloads. Old unpinned entries are removed automatically.

## Development

```sh
make build
make test
make app
```
