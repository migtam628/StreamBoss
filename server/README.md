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
git clone https://github.com/migtam628/StreamBoss.git
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
