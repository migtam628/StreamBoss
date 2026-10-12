# StreamBoss sync server

A small server of your own that keeps StreamBoss in step across your devices: settings, saved sources, profiles
and their PIN, My List, collections, watched marks, resume positions, edited channels and reminders. You sign in
with an e-mail and a password, in the app, under **Settings > Sync**.

- **No provider passwords ever reach it.** A saved source is sent without its password, and a playlist link that
  holds a login in its address is sent with that part taken out. Enter each provider password once on each device.
  The recently watched list is not synced either (its entries carry stream addresses, which hold the login).
- **Small and plain.** About 350 lines of Node.js, no packages to install, one SQLite file for the data. Passwords
  are stored hashed (scrypt); sign-in tokens are stored hashed too, so a copy of the database cannot be used to
  sign in.
- **Yours.** There is no StreamBoss service. If your server is off, StreamBoss works exactly as before, on each
  device by itself.

## Run it on a VPS (Docker, with automatic HTTPS)

You need a machine on the internet with Docker, a name for it (for example `sync.example.com`, with its DNS `A`
record pointing at the machine), and ports 80 and 443 open.

```sh
git clone https://github.com/migtam628/StreamBoss.git     # a private repository: sign in with a token or an SSH key
cd StreamBoss/server
cp .env.example .env        # put your name in SYNC_DOMAIN
docker compose up -d
```

[Caddy](https://caddyserver.com) gets and renews the certificate for that name by itself. Check it:
`curl https://sync.example.com/api/health` answers `{"ok":true,...}`.

Then, in StreamBoss on your first device: **Settings > Sync > Create an account**, with the server name, your
e-mail and a password of at least 8 characters. On the others: **Sign in** with the same.

### Who can create an account

`REGISTRATION` in `.env`:

| value | meaning |
| --- | --- |
| `first` (default) | Only the first account can be created: yours. Everyone else is refused. |
| `open` | Anyone who can reach the server can create an account (a family, a small group). |
| `closed` | No new accounts. |

Change it and run `docker compose up -d` again.

### On your own network, without a domain

`docker compose -f docker-compose.yml -f docker-compose.lan.yml up -d sync` publishes port 8080 without HTTPS; use
`http://<the machine's address>:8080` as the server. Only do this on a network you trust, and never expose that
port to the internet: the password and the token would travel in the clear.

## Host the website and the downloads

The repository is private, so GitHub Pages and public GitHub Releases are not available. The same machine serves the
website (https://streamboss.site) and the downloads instead, behind the same Caddy:

- `https://streamboss.site/` is the one-page website (`site/`).
- `https://streamboss.site/releases.json` lists the newest releases in the shape of GitHub's releases list. The app's
  **Check for updates**, the Roku installer and the website's download buttons read it.
- `https://streamboss.site/downloads/` lists each release's files; `downloads/latest/` has the newest build under
  a name without the version (`StreamBoss-android-arm64-v8a.apk`), for short links such as a Fire TV Downloader code.

CI sends the files with `rsync` over SSH when you tag a release (`release.yml`) and when `site/` changes on `main`
(`site.yml`).

**1. Point the name at the machine.** At your DNS provider, `streamboss.site`: `A` records to the machine's address
(delete the old GitHub Pages ones, and any `AAAA` that are not this machine's), and `www` as a `CNAME` to `streamboss.site`.

**2. Make the folder and a restricted key.** On the machine, as the user that will receive the files:

```sh
sudo mkdir -p /srv/streamboss/web/downloads && sudo chown -R "$USER": /srv/streamboss/web
ssh-keygen -t ed25519 -f streamboss-deploy -N "" -C streamboss-ci     # creates streamboss-deploy and .pub
```

Add the public key to `~/.ssh/authorized_keys` on one line, so it can only copy files into that folder (`rrsync` comes
with the `rsync` package; on some systems it is `/usr/bin/rrsync`, check `which rrsync`):

```
restrict,command="rrsync /srv/streamboss/web" ssh-ed25519 AAAA...the contents of streamboss-deploy.pub... streamboss-ci
```

**3. Give CI the key.** In the private repository: Settings > Secrets and variables > Actions > New repository secret:

| Secret | Value |
|---|---|
| `VPS_HOST` | the machine's address or name |
| `VPS_USER` | the user from step 2 |
| `VPS_SSH_KEY` | the whole contents of `streamboss-deploy` (the private key), then delete that file |
| `VPS_KNOWN_HOSTS` | the output of `ssh-keyscan -p 22 <the machine's address>` run from your own computer |
| `VPS_PORT` | only if SSH is not on port 22 |

A release run fails loudly (red) if these are missing, so a release is never silently left off the website.

**4. Start serving it.** In `.env` on the machine: `WEB_DOMAIN=streamboss.site` (and `WEB_ROOT` if you used another
folder). If something else already listens on port 443 at another address of the machine (Tailscale does, on its own
address), also set `BIND_IP` to the machine's public address, so Caddy takes ports 80 and 443 there only.

- **Without the sync server** (the website alone): `docker compose -f docker-compose.site.yml up -d`
- **Next to the sync server**: `docker compose -f docker-compose.yml -f docker-compose.web.yml up -d`

Caddy gets the certificates for `streamboss.site` and `www.streamboss.site` by itself (ports 80 and 443 must be open to the
internet). Run **Actions > Website > Run workflow** once to put the page there. The first tagged release creates
`releases.json` and the downloads.

**Housekeeping.** `releases.json` keeps the newest 12 releases; remove older folders from the machine now and then
(`downloads/latest` and the 12 newest stay):

```sh
cd /srv/streamboss/web/downloads && ls -d v* | sort -V | head -n -12 | xargs -r rm -rf
```

## Run MooBee on the same machine

[MooBee](https://github.com/migtam628/moobee) (a movie and TV discovery site) can run next to the sync server, behind the same
Caddy, on its own name such as `moobee.streamboss.site`. It builds from its repository's `Dockerfile`.

```sh
cp moobee.env.example moobee.env      # put your TMDB read token in it
# in .env: MOOBEE_DOMAIN=moobee.streamboss.site   (its DNS A record must point at this machine)
docker compose -f docker-compose.site.yml -f docker-compose.moobee.yml up -d --build
# with the sync server: -f docker-compose.yml -f docker-compose.web.yml -f docker-compose.moobee.yml
```

All the files at once: set `COMPOSE_FILE=docker-compose.site.yml:docker-compose.moobee.yml` in
`.env` and run `docker compose up -d --build`. To update MooBee later: `docker compose up -d --build moobee`.
The TMDB token is read from `moobee.env` on the machine only; it is never in an image or a repository.

### Backups and updates

Everything is in the `sync-data` Docker volume (`streamboss-sync.db`).

```sh
docker compose stop sync
docker run --rm -v server_sync-data:/data -v "$PWD":/backup alpine tar czf /backup/sync-data.tgz -C /data .
docker compose start sync
```

(The volume is called `<folder>_sync-data`; `docker volume ls` shows the name.) To update: `git pull`, then
`docker compose up -d --build`. Losing the server does not lose anything on the devices: they keep their data and
sign in again to a new server, which is filled from them.

### Without Docker

Node.js 22.13 or later (it has SQLite built in):

```sh
cd server
DATA_DIR=./data PORT=8080 REGISTRATION=first node src/main.js
```

Put a reverse proxy with HTTPS in front of it and set `TRUST_PROXY=1` so the address of the caller is read from
`X-Forwarded-For` (used to slow down password guessing: ten wrong tries in ten minutes from one address, then a
wait). Do not set it without a proxy.

## Settings

| variable | default | meaning |
| --- | --- | --- |
| `PORT` | `8080` | port to listen on |
| `DATA_DIR` | `./data` (`/data` in Docker) | where the database is |
| `REGISTRATION` | `first` | `first`, `open` or `closed` (above) |
| `TRUST_PROXY` | off (on in the compose file) | read the caller's address from `X-Forwarded-For` |
| `ALLOWED_ORIGINS` | `*` | the web address of StreamBoss on the web, if you use it (CORS) |

## What it stores

For every account: the e-mail, a scrypt hash of the password, one row per sign-in (device name and the SHA-256 of
its token), and one row per synced preference: its name, its value as text, a revision number. The values are the
ones StreamBoss keeps in its own preferences, including your TMDB and OpenSubtitles API keys when you set them
(not the OpenSubtitles password). Nothing is logged except start-up and unexpected errors.

## How sync works (for the curious)

The app compares every synced preference with the copy it saved at the last sync and with the server's. What this
device changed since is laid over what the server has now: a favorite added here and another added on your phone
both stay; a title removed on one device is removed on the other; for a setting changed on two devices the one
that syncs last wins. Each write names the revision it builds on and the server refuses it if another device wrote
first, so the app merges again and retries. No change is lost to a race.

## API

All bodies are JSON. Calls after the first two need `Authorization: Bearer <token>`.

| call | does |
| --- | --- |
| `GET /api/health` | `{ok, version, registration}` |
| `POST /api/register` `{email, password, device}` | create an account; returns `{token, email}` |
| `POST /api/login` `{email, password, device}` | sign in; returns `{token, email}` |
| `POST /api/logout` | end this token |
| `GET /api/me` | the account and its signed-in devices |
| `POST /api/password` `{old, new}` | change the password; other devices are signed out |
| `DELETE /api/account` `{password}` | delete the account and all its data |
| `GET /api/data` | `{items: {key: {value, rev, updated}}}` |
| `PUT /api/data/<key>` `{value, base}` | write `value` (text, or `null` to remove) on top of revision `base`; `409` with the current `{rev, value}` when `base` is old |

## Tests

`npm test` in this folder (Node 22.13 or later).
