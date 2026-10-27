# secrets/

One file per secret, holding just the value (no trailing newline needed).
`./deploy.sh` streams them into `/var/lib/secrets` on the server (root-only);
they never enter the Nix store. Keep this directory encrypted with
[git-crypt](https://github.com/AGWA/git-crypt) (`.gitattributes` already
covers it): `git-crypt init`, then save `git-crypt export-key - | base64` in
your password manager.

The server lists any required one that's missing:
`journalctl -u spudbox-secrets`.

## Required, depending on your settings

| File | When |
| --- | --- |
| `plex/username`, `plex/password` | Always: your plex.tv login, used once to get a token. Or put a token in `plex/token` instead. |
| `usenet/username`, `usenet/password` | `usenet.servers` is set |
| `<indexer>/api-key` (e.g. `nzbgeek/api-key`) | for each of `indexers` |
| `cloudflare/api-token` | `tls = "cloudflare"` (Zone:DNS:Edit on your domain) |
| `opensubtitles/username`, `opensubtitles/password` | `subtitleProviders` has `opensubtitlescom` |
| `assrt/api-token` | `subtitleProviders` has `assrt` |
| `pushover/app-token`, `pushover/user-key` | `pushover.enable` |
| `r2/s3-credentials.env` | `offsiteBackup.enable`; lines `AWS_ACCESS_KEY_ID=...` and `AWS_SECRET_ACCESS_KEY=...` |

## Optional

Generated on the server on first boot if absent; supply them only to choose
the values yourself. `sudo spudbox-passwords` on the server prints the logins.

| File | What |
| --- | --- |
| `admin/username` | The login name for every web UI (default `admin`) |
| `<service>/password` | That web UI's password (sonarr, radarr, bazarr, sabnzbd, transmission, tautulli, audiobookshelf, homebridge) |
| `sonarr/api-key`, `radarr/api-key`, `sabnzbd/api-key`, `sabnzbd/nzb-key` | API keys |
| `restic/password` | Encrypts the backups. **Copy it into your password manager**: without it no backup can be restored. |
| `users/<name>/hashed` | A password hash for a login user (`mkpasswd -m yescrypt`); without one, SSH keys only |
| `users/<name>/plaintext` | Your own recovery copy of that password. Never copied to the server. |
