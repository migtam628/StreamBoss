# MooBee signed-HLS renewal (native, draft)

Companion to MooBee IPTV PR #15 (stacked on token-revocation PR #14).

- After signing in to an Xtream provider, StreamBoss reads the optional
  `moobee_hls_refresh_after_seconds` hint from authenticated `user_info`.
- Without the hint, non-MooBee providers work exactly as before.
- For native movie/episode `.m3u8` entry URLs only, record the original player
  opening time, shared across Watch and full-screen playback.
- Every five seconds, when the lease is due (normally at three hours),
  preflight the original authenticated URL. On a valid fresh playlist,
  reopen media at the saved position and retain playback/pause state and rate.
  No video URL, password, or bearer token is written to application logs.
- If preflight fails, keep the old playback session and retry after two
  minutes. Old tokens still expire normally, so retries cannot promise
  uninterrupted playback in an extended outage.
- Disable this behavior in the browser: cross-origin/local-network access
  remains subject to browser security and production HTTPS/CORS policy.
- The initial entry URL still embeds Xtream credentials and **must** be
  protected with HTTPS in production and excluded from access/error logging.

## Validation gates

The renewal branch is not released or deployed. Run Flutter analyze/tests
and a native macOS build before installing it. Test against localhost
`18001` through SSH only with a new **separate test account** and the
updated opt-in staging gateway. Do not alter the working port `18000`
instance, production MooBee IPTV, or PR #14 rollback files.

Use accelerated policy/unit tests plus actual playback:
1. Old provider unaffected, no automatic reopening.
2. HLS-enabled stage advertises hint, authenticated movie/episode play.
3. Force a short renewal interval in *test-only* configuration; observe
   recovery of position, pause state, and rate.
4. Watch ↔ fullscreen handoff retains one lease clock.
5. Reject wrong password and disabled subscriber; old tokens stay revoked.
6. After pausing/resuming, app remains stable; no credential leakage.
7. More than four hours sustained playback without 401 errors.

## Limitations

This is proactive playback reopening, not true gapless renewal. A short
rebuffer can occur at re-open. In-app preflight does not authorize or keep
alive a disabled account; the server remains authoritative. Browser
playback, mobile background behavior and concurrency need separate QA.
