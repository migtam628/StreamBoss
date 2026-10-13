#!/usr/bin/env bash
# Sends one release to the website server: the files, the "latest" folder and the release list (releases.json).
# Run from a folder that has artifacts/ (the release files) and notes.md (the release notes).
# Environment: TAG, PRERELEASE (true or false), VPS_HOST, VPS_USER, VPS_SSH_KEY, VPS_KNOWN_HOSTS, optional VPS_PORT.
# Used by .github/workflows/release.yml and publish-downloads.yml; see server/README.md.
set -euo pipefail

: "${TAG:?TAG is not set}"
for v in VPS_HOST VPS_USER VPS_SSH_KEY VPS_KNOWN_HOSTS; do
  if [ -z "${!v:-}" ]; then
    echo "::error::The website server secrets are not set ($v is empty), so $TAG was NOT published to the website. See server/README.md."
    exit 1
  fi
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 700 -d ~/.ssh
printf '%s\n' "$VPS_SSH_KEY" > ~/.ssh/deploy_key
chmod 600 ~/.ssh/deploy_key
printf '%s\n' "$VPS_KNOWN_HOSTS" > ~/.ssh/known_hosts
PORT="${VPS_PORT:-22}"
KEY="$VPS_HOST"; [ "$PORT" != "22" ] && KEY="[$VPS_HOST]:$PORT"
if ! ssh-keygen -F "$KEY" -f ~/.ssh/known_hosts >/dev/null 2>&1; then
  echo "::error::VPS_KNOWN_HOSTS has no line for $KEY. Run  ssh-keyscan -t ed25519 -p $PORT $VPS_HOST  on your own computer and put its output (one line starting with $VPS_HOST) in that secret."
  exit 1
fi
SSH="ssh -i $HOME/.ssh/deploy_key -p $PORT -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
DEST="$VPS_USER@$VPS_HOST"

# The list as it is now. Only "not found" means a first release; any other failure stops here, so the
# history is never replaced by an empty list.
code="$(curl -sS -o feed.json -w '%{http_code}' --retry 3 https://streamboss.site/releases.json || true)"
case "$code" in
  200) ;;
  404) echo '[]' > feed.json ;;
  *) echo "::error::Could not read the current releases.json (HTTP $code)"; exit 1 ;;
esac

touch notes.md
python3 "$HERE/make_manifest.py" --tag "$TAG" --artifacts artifacts --notes notes.md \
  --prerelease "${PRERELEASE:-false}" --feed feed.json --out releases.json --latest-dir latest

# Files first, the list last: nobody is pointed at a file that is not there yet.
RS=(rsync -a --chmod=D755,F644 -e "$SSH")
"${RS[@]}" artifacts/ "$DEST:downloads/$TAG/"
"${RS[@]}" --delete latest/ "$DEST:downloads/latest/"
"${RS[@]}" releases.json "$DEST:releases.json"

# StreamBoss on the web (https://web.streamboss.site): the web build of this release replaces the one there. It goes
# to webapp/ inside the same folder, so the same restricted key is enough. A release without a web build leaves it alone.
WEBZIP="$(ls artifacts/StreamBoss-*-web.zip 2>/dev/null | head -n 1 || true)"
if [ -n "$WEBZIP" ]; then
  rm -rf webapp && mkdir webapp && unzip -q "$WEBZIP" -d webapp
  if [ ! -f webapp/index.html ]; then
    echo "::error::$WEBZIP has no index.html, so the web app was NOT updated."
    exit 1
  fi
  "${RS[@]}" --delete webapp/ "$DEST:webapp/"
  echo "Updated the web app to $TAG."
else
  echo "No web build in this release; the web app was left as it is."
fi
echo "Published $TAG to the website server."
