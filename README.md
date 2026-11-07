# ShowVol

A tiny macOS menu bar app that shows free space on every mounted volume (internal and external) and lets you fuzzy-search folder names to see which volume they live on.

- Click the V icon in the menu bar to see each volume's capacity.
- Type in the search box (e.g. `prjdoc` finds `Project Documents`); each result shows its volume and full path. Click to reveal in Finder, right-click to copy the path.
- Search uses Spotlight (`mdfind`), so volumes with indexing disabled aren't searched.

## Install

```
./install.sh
```

Builds with `swiftc` (Xcode Command Line Tools), installs to `/Applications`, adds a login item, and launches it.
