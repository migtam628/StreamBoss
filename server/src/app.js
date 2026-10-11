// The HTTP API. No framework, no dependencies: Node's own http server and a small router.
import { createServer } from 'node:http';
import { openDb } from './db.js';
import { hashPassword, verifyPassword, spendTime, newToken, tokenHash, normalizeEmail, MIN_PASSWORD } from './auth.js';

export const VERSION = '0.1.0';
const MAX_BODY = 2 * 1024 * 1024; // one value is at most 2 MB
const MAX_KEYS = 2000; // per user
const MAX_TOTAL = 32 * 1024 * 1024; // per user, all values together
const KEY = /^[A-Za-z0-9:._~-]{1,200}$/;

class HttpError extends Error {
  constructor(status, message, extra = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

/**
 * Options: dataDir (':memory:' for tests), registration ('first' = only the first account, 'open' = anyone,
 * 'closed' = nobody), trustProxy (read the caller's address from X-Forwarded-For; only behind your own proxy),
 * origins (CORS, for the web build), now (a clock, for tests).
 */
export function createApp(opts = {}) {
  const dataDir = opts.dataDir ?? process.env.DATA_DIR ?? './data';
  const registration = opts.registration ?? process.env.REGISTRATION ?? 'first';
  const trustProxy = opts.trustProxy ?? process.env.TRUST_PROXY === '1';
  const origins = opts.origins ?? process.env.ALLOWED_ORIGINS ?? '*';
  const now = opts.now ?? Date.now;
  const db = openDb(dataDir);

  const q = {
    userByEmail: db.prepare('SELECT * FROM users WHERE email = ?'),
    userCount: db.prepare('SELECT COUNT(*) AS n FROM users'),
    addUser: db.prepare('INSERT INTO users (email, pass, created) VALUES (?, ?, ?)'),
    addSession: db.prepare('INSERT INTO sessions (user_id, token_hash, device, created, used) VALUES (?, ?, ?, ?, ?)'),
    session: db.prepare('SELECT s.id AS sid, s.user_id, u.email FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?'),
    touch: db.prepare('UPDATE sessions SET used = ? WHERE id = ?'),
    dropSession: db.prepare('DELETE FROM sessions WHERE id = ?'),
    dropOtherSessions: db.prepare('DELETE FROM sessions WHERE user_id = ? AND id != ?'),
    sessionsOf: db.prepare('SELECT id, device, created, used FROM sessions WHERE user_id = ? ORDER BY used DESC'),
    setPass: db.prepare('UPDATE users SET pass = ? WHERE id = ?'),
    userById: db.prepare('SELECT * FROM users WHERE id = ?'),
    dropUser: db.prepare('DELETE FROM users WHERE id = ?'),
    items: db.prepare('SELECT k, v, rev, updated FROM items WHERE user_id = ?'),
    item: db.prepare('SELECT v, rev FROM items WHERE user_id = ? AND k = ?'),
    putItem: db.prepare(
      'INSERT INTO items (user_id, k, v, rev, updated) VALUES (?, ?, ?, ?, ?) ' +
        'ON CONFLICT (user_id, k) DO UPDATE SET v = excluded.v, rev = excluded.rev, updated = excluded.updated'
    ),
    usage: db.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(LENGTH(v)), 0) AS bytes FROM items WHERE user_id = ?'),
  };

  // Too many wrong sign-ins from one address: slow down. In memory, which is enough for one small server.
  const attempts = new Map();
  const WINDOW = 10 * 60 * 1000, MAX_ATTEMPTS = 10;
  function gate(ip) {
    const t = now();
    const a = (attempts.get(ip) ?? []).filter((x) => t - x < WINDOW);
    if (a.length >= MAX_ATTEMPTS) throw new HttpError(429, 'Too many attempts. Wait a few minutes and try again.');
    a.push(t);
    attempts.set(ip, a);
    if (attempts.size > 5000) for (const [k, v] of attempts) if (!v.some((x) => t - x < WINDOW)) attempts.delete(k);
  }
  const forgive = (ip) => attempts.delete(ip);

  const readBody = (req) =>
    new Promise((resolve, reject) => {
      const parts = [];
      let size = 0;
      // A body that is too large is read and thrown away (so the sender gets the answer, not a broken connection).
      req.on('data', (c) => {
        size += c.length;
        if (size <= MAX_BODY) parts.push(c);
      });
      req.on('end', () => {
        if (size > MAX_BODY) return reject(new HttpError(413, 'That is too large.'));
        if (!size) return resolve({});
        try {
          const j = JSON.parse(Buffer.concat(parts).toString('utf8'));
          if (j === null || typeof j !== 'object' || Array.isArray(j)) throw new Error('not an object');
          resolve(j);
        } catch {
          reject(new HttpError(400, 'The request is not valid JSON.'));
        }
      });
      req.on('error', reject);
    });

  const device = (v) => String(v ?? 'unknown device').slice(0, 80);

  function auth(req) {
    const m = /^Bearer (\S{20,200})$/.exec(req.headers.authorization ?? '');
    const row = m && q.session.get(tokenHash(m[1]));
    if (!row) throw new HttpError(401, 'You are signed out. Sign in again.');
    q.touch.run(now(), row.sid);
    return row;
  }

  async function issue(user, dev) {
    const token = newToken();
    q.addSession.run(user.id, tokenHash(token), device(dev), now(), now());
    return { token, email: user.email };
  }

  // --- Routes ---------------------------------------------------------------------------------------

  async function route(req, url, ip) {
    const { method } = req;
    const path = url.pathname;

    if (method === 'GET' && path === '/api/health') return [200, { ok: true, version: VERSION, registration }];

    if (method === 'POST' && path === '/api/register') {
      gate(ip);
      const b = await readBody(req);
      const email = normalizeEmail(b.email);
      if (!email) throw new HttpError(400, 'That does not look like an e-mail address.');
      if (typeof b.password !== 'string' || b.password.length < MIN_PASSWORD)
        throw new HttpError(400, `The password needs at least ${MIN_PASSWORD} characters.`);
      if (b.password.length > 200) throw new HttpError(400, 'That password is too long.');
      const first = q.userCount.get().n === 0;
      if (registration === 'closed' || (registration === 'first' && !first))
        throw new HttpError(403, 'New accounts are not being accepted on this server.');
      if (q.userByEmail.get(email)) throw new HttpError(409, 'There is already an account with that e-mail.');
      const info = q.addUser.run(email, await hashPassword(b.password), now());
      return [201, await issue({ id: Number(info.lastInsertRowid), email }, b.device)];
    }

    if (method === 'POST' && path === '/api/login') {
      gate(ip);
      const b = await readBody(req);
      const email = normalizeEmail(b.email);
      const user = email && q.userByEmail.get(email);
      const ok = user ? await verifyPassword(String(b.password ?? ''), user.pass) : (await spendTime(String(b.password ?? '')), false);
      if (!ok) throw new HttpError(401, 'The e-mail or the password is wrong.');
      forgive(ip);
      return [200, await issue(user, b.device)];
    }

    // Everything below needs a token.
    const s = auth(req);

    if (method === 'POST' && path === '/api/logout') {
      q.dropSession.run(s.sid);
      return [204, null];
    }

    if (method === 'GET' && path === '/api/me') {
      return [200, { email: s.email, devices: q.sessionsOf.all(s.user_id).map((d) => ({ ...d, current: d.id === s.sid })) }];
    }

    if (method === 'POST' && path === '/api/password') {
      gate(ip);
      const b = await readBody(req);
      const user = q.userById.get(s.user_id);
      if (!(await verifyPassword(String(b.old ?? ''), user.pass))) throw new HttpError(401, 'The current password is wrong.');
      if (typeof b.new !== 'string' || b.new.length < MIN_PASSWORD || b.new.length > 200)
        throw new HttpError(400, `The new password needs at least ${MIN_PASSWORD} characters.`);
      q.setPass.run(await hashPassword(b.new), s.user_id);
      q.dropOtherSessions.run(s.user_id, s.sid); // other devices have to sign in again
      forgive(ip);
      return [204, null];
    }

    if (method === 'DELETE' && path === '/api/account') {
      gate(ip);
      const b = await readBody(req);
      const user = q.userById.get(s.user_id);
      if (!(await verifyPassword(String(b.password ?? ''), user.pass))) throw new HttpError(401, 'The password is wrong.');
      q.dropUser.run(s.user_id); // sessions and items go with it
      forgive(ip);
      return [204, null];
    }

    if (method === 'GET' && path === '/api/data') {
      const items = {};
      for (const r of q.items.all(s.user_id)) items[r.k] = { value: r.v, rev: r.rev, updated: r.updated };
      return [200, { items }];
    }

    const m = /^\/api\/data\/([^/]+)$/.exec(path);
    if (m && method === 'PUT') {
      let key;
      try {
        key = decodeURIComponent(m[1]);
      } catch {
        throw new HttpError(400, 'That key is not valid.');
      }
      if (!KEY.test(key)) throw new HttpError(400, 'That key is not valid.');
      const b = await readBody(req);
      if (b.value !== null && typeof b.value !== 'string') throw new HttpError(400, 'The value has to be text, or null to remove it.');
      if (!Number.isInteger(b.base) || b.base < 0) throw new HttpError(400, 'Say which revision this builds on (base).');
      const cur = q.item.get(s.user_id, key);
      const rev = cur?.rev ?? 0;
      if (rev !== b.base) throw new HttpError(409, 'Changed elsewhere in the meantime.', { rev, value: cur?.v ?? null });
      const u = q.usage.get(s.user_id);
      if (!cur && u.n >= MAX_KEYS) throw new HttpError(413, 'Too many items are stored for this account.');
      if (u.bytes - (cur?.v?.length ?? 0) + (b.value?.length ?? 0) > MAX_TOTAL) throw new HttpError(413, 'This account is out of space.');
      q.putItem.run(s.user_id, key, b.value, rev + 1, now());
      return [200, { rev: rev + 1 }];
    }

    throw new HttpError(404, 'Not found.');
  }

  // --- Server ---------------------------------------------------------------------------------------

  const server = createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://x');
    const fwd = trustProxy ? String(req.headers['x-forwarded-for'] ?? '').split(',').pop().trim() : '';
    const ip = fwd || req.socket.remoteAddress || 'unknown';
    const headers = {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'access-control-allow-origin': origins,
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'access-control-max-age': '86400',
    };
    try {
      if (req.method === 'OPTIONS') {
        res.writeHead(204, headers).end();
        return;
      }
      if (!url.pathname.startsWith('/api/')) throw new HttpError(404, 'Not found.');
      if (Number(req.headers['content-length'] ?? 0) > 16 * 1024 * 1024) {
        res.writeHead(413, { ...headers, connection: 'close' }).end(JSON.stringify({ error: 'That is too large.' }));
        return;
      }
      const [status, body] = await route(req, url, ip);
      res.writeHead(status, headers).end(body === null ? undefined : JSON.stringify(body));
    } catch (e) {
      if (!(e instanceof HttpError)) console.error('error:', e?.message ?? e);
      const err = e instanceof HttpError ? e : new HttpError(500, 'Something went wrong on the server.');
      if (!res.headersSent) res.writeHead(err.status, headers);
      res.end(JSON.stringify({ error: err.message, ...err.extra }));
    }
  });

  return { server, db, close: () => new Promise((r) => server.close(() => (db.close(), r()))) };
}
