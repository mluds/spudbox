# spudbox

**Turn a spare PC into a home media server that runs itself.**

spudbox sets up a server that streams your movies, TV shows and audiobooks
to every screen in the house. Once it's installed:

- **Watch** in the Plex app on your TV, phone, tablet or browser. Streaming
  away from home needs a [Plex Pass](https://www.plex.tv/plex-pass/).
- **Request** a movie or show in Jellyseerr. It's downloaded, filed and
  subtitled, and shows up in Plex when the download finishes. New episodes
  of the shows you follow arrive on their own.
- **Share** your library with family and friends. They can make requests
  too.
- **Leave it alone.** It backs itself up every night and can alert your
  phone when something fails.

You describe the server in one settings file, and spudbox installs and
connects about a dozen apps on [NixOS](https://nixos.org). You don't need to
know NixOS: Claude Code does the install.

## Installation

Install [Claude Code](https://claude.com/claude-code), then run:

```bash
git clone https://github.com/mluds/spudbox
cd spudbox
claude
```

Type `/install-spudbox`. It asks for everything it needs and walks you
through the rest.

Requirements, the apps, day-to-day use and backups are in the
[guide](docs/GUIDE.md).

## License

MIT; see [LICENSE](LICENSE).
