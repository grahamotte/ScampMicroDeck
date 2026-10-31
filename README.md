# Scamp Micro Deck

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="assets/screenshot-2.png" alt="Scamp Micro Deck screenshot">
</p>
<!-- markdownlint-enable MD033 -->

Scamp Micro Deck is a native macOS music player for local folders of audio files, designed to mimic the tedious charm of a real vinyl record player.

Learn more at [scampmicrodeck.com](https://scampmicrodeck.com).

## Install

<!-- markdownlint-disable MD033 -->
<a href="https://apps.apple.com/us/app/scamp-micro-deck/id6761630397?mt=12">
  <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us?size=250x83&releaseDate=1775001600" alt="Download on the Mac App Store" height="40">
</a>
<!-- markdownlint-enable MD033 -->

Or install with Homebrew:

```sh
brew install grahamotte/tap/scamp-micro-deck
```

Each release is also available from [GitHub Releases](https://github.com/grahamotte/ScampMicroDeck/releases).

## Using Scamp Micro Deck

An album is a folder. Scamp Micro Deck plays every audio file in the folder as one record, in filename order, and shows an image from the folder as the cover.

- **Library:** Click the eject button to open or close your record shelf. The first time, choose your music folder, organized as Artist › Album › songs and cover art. On the shelf, images named `cover`, `folder`, `front`, or `album` are preferred as covers. Click a cover to load it. The shelf stays open so switching records is quick.
- **Load a single album:** Drag an album folder into the window, or choose **Library > Open Album Folder…** (⌘O).
- **Try it out:** **Help > Load Demo Album** loads a bundled sample record.
- **Play and pause:** The platter spins up when you press play and spins down before pausing, and the music speeds up and slows down with it. Playback stops at the end of the record.
- **Tonearm:** Drag the tonearm across the record to move through the album. Hold Shift or Command while dragging to snap to the start of the nearest track.
- **Hold the record:** Press and hold on the record to slow it to half speed. Let go to bring it back up to speed.
- **Switching records:** Choosing a different cover while music is playing swaps albums and starts the new record from the beginning.
- **Media keys:** Play, pause, next, and previous track work from the keyboard media keys and Control Center.

When you reopen the app, it reloads the last record at the track and position where you left off.

### Library menu

- **Choose Music Folder…** / **Change Music Folder…** sets the folder the shelf is built from.
- **Sort** orders the shelf by **Artist, Then Album**, **Album**, **Most Played**, or **Recently Added**.
- **Clear Library and Stats** forgets the music folder and resets play counts and history.

### Themes

The **Theme** menu sets the table (Walnut, Wood, Frosted Glass, Rainbow, White Marble, Black Marble), the record (Black, Yellow, Red, Pink Splatter, Blue Splatter), and the controls (Silver, Black, Gold). **Randomize Themes** picks one of each.

The how-to-use guide is in **Help > Scamp Micro Deck Help** (⇧⌘/). Scamp Micro Deck does not collect any personal information or telemetry.

## Contributing

Issues welcome.

## License

[MIT](LICENSE)
