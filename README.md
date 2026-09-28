# Scamp Micro Deck

Scamp Micro Deck is a native macOS music player for local folders of audio files, designed to mimic the tedious charm of a real vinyl record player.

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="assets/screenshot-2.png" alt="Scamp Micro Deck screenshot">
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/scamp-micro-deck/id6761630397?mt=12">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us?size=250x83&releaseDate=1775001600" alt="Download on the Mac App Store" height="40">
  </a>
</p>
<!-- markdownlint-enable MD033 -->

## Contributing

Issues and PRs welcome.

Tools:

- `mise test` - run the full test suite
- `mise simulate macos` - build and launch the macOS app
- `mise publish:set_version 1.5.0` - update release and Xcode versions
- `mise publish` - archive, upload, submit, notarize, and publish a release

`mise publish` uses the App Store Connect, signing certificate, Codeberg, and GitHub credentials in the ignored `.env.production` file.

## License

MIT
