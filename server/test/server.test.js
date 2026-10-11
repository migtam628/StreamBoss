import { test, before, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';

async function start(opts = {}) {
  const app = createApp({ dataDir: ':memory:', ...opts });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const call = async (method, path, body, token) => {
    const res = await fetch(base + path, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  return { app, call };
}

describe('accounts', () => {
  let s;
  before(async () => (s = await start()));
  after(() => s.app.close());

  test('health says what the server is', async () => {
    const r = await s.call('GET', '/api/health');
    assert.equal(r.status, 200);
    assert.equal(r.body.ok, true);
  });

  test('the first account can register; with the default setting nobody else can', async () => {
    const a = await s.call('POST', '/api/register', { email: 'Me@Example.com', password: 'correct horse', device: 'laptop' });
    assert.equal(a.status, 201);
    assert.equal(a.body.email, 'me@example.com');
    assert.ok(a.body.token.length >= 40);
    const b = await s.call('POST', '/api/register', { email: 'other@example.com', password: 'correct horse' });
    assert.equal(b.status, 403);
  });

  test('bad e-mail and short password are refused in words', async () => {
    const s2 = await start();
    const e = await s2.call('POST', '/api/register', { email: 'nope', password: 'correct horse' });
    assert.equal(e.status, 400);
    assert.match(e.body.error, /e-mail/);
    const p = await s2.call('POST', '/api/register', { email: 'a@b.co', password: 'short' });
    assert.equal(p.status, 400);
    assert.match(p.body.error, /8 characters/);
    await s2.app.close();
  });

  test('sign in works with the right password only, whatever the e-mail capitals', async () => {
    const ok = await s.call('POST', '/api/login', { email: 'ME@example.com', password: 'correct horse' });
    assert.equal(ok.status, 200);
    const bad = await s.call('POST', '/api/login', { email: 'me@example.com', password: 'wrong horse!' });
    assert.equal(bad.status, 401);
    const unknown = await s.call('POST', '/api/login', { email: 'nobody@example.com', password: 'correct horse' });
    assert.equal(unknown.status, 401);
    assert.equal(unknown.body.error, bad.body.error); // does not say which part was wrong
  });

  test('a token is needed, and logging out ends it', async () => {
    assert.equal((await s.call('GET', '/api/me')).status, 401);
    assert.equal((await s.call('GET', '/api/me', undefined, 'x'.repeat(43))).status, 401);
    const { body } = await s.call('POST', '/api/login', { email: 'me@example.com', password: 'correct horse', device: 'phone' });
    const me = await s.call('GET', '/api/me', undefined, body.token);
    assert.equal(me.status, 200);
    assert.equal(me.body.email, 'me@example.com');
    assert.ok(me.body.devices.some((d) => d.device === 'phone' && d.current));
    assert.equal((await s.call('POST', '/api/logout', {}, body.token)).status, 204);
    assert.equal((await s.call('GET', '/api/me', undefined, body.token)).status, 401);
  });

  test('changing the password signs the other devices out', async () => {
    const a = (await s.call('POST', '/api/login', { email: 'me@example.com', password: 'correct horse' })).body.token;
    const b = (await s.call('POST', '/api/login', { email: 'me@example.com', password: 'correct horse' })).body.token;
    assert.equal((await s.call('POST', '/api/password', { old: 'nope nope', new: 'a better one 1' }, a)).status, 401);
    assert.equal((await s.call('POST', '/api/password', { old: 'correct horse', new: 'a better one 1' }, a)).status, 204);
    assert.equal((await s.call('GET', '/api/me', undefined, a)).status, 200);
    assert.equal((await s.call('GET', '/api/me', undefined, b)).status, 401);
    assert.equal((await s.call('POST', '/api/login', { email: 'me@example.com', password: 'correct horse' })).status, 401);
    assert.equal((await s.call('POST', '/api/login', { email: 'me@example.com', password: 'a better one 1' })).status, 200);
  });
});

describe('registration settings', () => {
  test('open lets anyone register; closed lets nobody', async () => {
    const open = await start({ registration: 'open' });
    assert.equal((await open.call('POST', '/api/register', { email: 'a@x.io', password: 'password one' })).status, 201);
    assert.equal((await open.call('POST', '/api/register', { email: 'b@x.io', password: 'password two' })).status, 201);
    assert.equal((await open.call('POST', '/api/register', { email: 'b@x.io', password: 'password two' })).status, 409);
    await open.app.close();
    const closed = await start({ registration: 'closed' });
    assert.equal((await closed.call('POST', '/api/register', { email: 'a@x.io', password: 'password one' })).status, 403);
    await closed.app.close();
  });
});

describe('sign-in attempts', () => {
  test('ten wrong tries from one address, then it waits', async () => {
    let t = 1_000_000;
    const s = await start({ registration: 'open', now: () => t });
    await s.call('POST', '/api/register', { email: 'a@x.io', password: 'password one' });
    let last;
    for (let i = 0; i < 12; i++) last = await s.call('POST', '/api/login', { email: 'a@x.io', password: 'wrong wrong' });
    assert.equal(last.status, 429);
    t += 11 * 60 * 1000;
    assert.equal((await s.call('POST', '/api/login', { email: 'a@x.io', password: 'password one' })).status, 200);
    await s.app.close();
  });
});

describe('data', () => {
  let s, token, other;
  before(async () => {
    s = await start({ registration: 'open' });
    token = (await s.call('POST', '/api/register', { email: 'a@x.io', password: 'password one' })).body.token;
    other = (await s.call('POST', '/api/register', { email: 'b@x.io', password: 'password two' })).body.token;
  });
  after(() => s.app.close());

  test('a value is stored with a revision that goes up', async () => {
    const r1 = await s.call('PUT', '/api/data/favorites', { value: '{"t":"l","v":["a"]}', base: 0 }, token);
    assert.deepEqual(r1, { status: 200, body: { rev: 1 } });
    const r2 = await s.call('PUT', '/api/data/favorites', { value: '{"t":"l","v":["a","b"]}', base: 1 }, token);
    assert.equal(r2.body.rev, 2);
    const all = await s.call('GET', '/api/data', undefined, token);
    assert.equal(all.body.items.favorites.value, '{"t":"l","v":["a","b"]}');
    assert.equal(all.body.items.favorites.rev, 2);
  });

  test('a write built on an old revision is refused and shows what is there now', async () => {
    const r = await s.call('PUT', '/api/data/favorites', { value: '{"t":"l","v":["z"]}', base: 1 }, token);
    assert.equal(r.status, 409);
    assert.equal(r.body.rev, 2);
    assert.equal(r.body.value, '{"t":"l","v":["a","b"]}');
    const fresh = await s.call('PUT', '/api/data/brand-new', { value: 'x', base: 3 }, token);
    assert.equal(fresh.status, 409);
    assert.equal(fresh.body.rev, 0);
  });

  test('null removes a value but keeps the revision, so other devices learn of it', async () => {
    await s.call('PUT', '/api/data/gone', { value: 'x', base: 0 }, token);
    const del = await s.call('PUT', '/api/data/gone', { value: null, base: 1 }, token);
    assert.equal(del.body.rev, 2);
    const all = await s.call('GET', '/api/data', undefined, token);
    assert.equal(all.body.items.gone.value, null);
    assert.equal(all.body.items.gone.rev, 2);
  });

  test('one account never sees another account\'s data', async () => {
    const mine = await s.call('GET', '/api/data', undefined, other);
    assert.deepEqual(mine.body.items, {});
    const w = await s.call('PUT', '/api/data/favorites', { value: 'theirs', base: 0 }, other);
    assert.equal(w.status, 200);
    const a = await s.call('GET', '/api/data', undefined, token);
    assert.notEqual(a.body.items.favorites.value, 'theirs');
  });

  test('bad keys and values are refused', async () => {
    assert.equal((await s.call('PUT', '/api/data/' + encodeURIComponent('a b'), { value: 'x', base: 0 }, token)).status, 400);
    assert.equal((await s.call('PUT', '/api/data/' + 'k'.repeat(201), { value: 'x', base: 0 }, token)).status, 400);
    assert.equal((await s.call('PUT', '/api/data/k1', { value: 5, base: 0 }, token)).status, 400);
    assert.equal((await s.call('PUT', '/api/data/k1', { value: 'x' }, token)).status, 400);
    assert.equal((await s.call('PUT', '/api/data/k1', { value: 'x', base: 0 })).status, 401);
  });

  test('keys with a colon (a profile\'s) are fine', async () => {
    const r = await s.call('PUT', '/api/data/' + encodeURIComponent('positions:p1abc'), { value: '{}', base: 0 }, token);
    assert.equal(r.status, 200);
  });

  test('a value over the limit is refused', async () => {
    const big = 'x'.repeat(2 * 1024 * 1024 + 10);
    const r = await s.call('PUT', '/api/data/big', { value: big, base: 0 }, token);
    assert.equal(r.status, 413);
  });

  test('deleting the account deletes the data and the sign-ins', async () => {
    const t = (await s.call('POST', '/api/register', { email: 'c@x.io', password: 'password three' })).body.token;
    await s.call('PUT', '/api/data/k', { value: 'v', base: 0 }, t);
    assert.equal((await s.call('DELETE', '/api/account', { password: 'wrong wrong' }, t)).status, 401);
    assert.equal((await s.call('DELETE', '/api/account', { password: 'password three' }, t)).status, 204);
    assert.equal((await s.call('GET', '/api/data', undefined, t)).status, 401);
    assert.equal((await s.call('POST', '/api/login', { email: 'c@x.io', password: 'password three' })).status, 401);
    const n = s.app.db.prepare('SELECT COUNT(*) AS n FROM items WHERE k = ?').get('k').n;
    assert.equal(n, 0);
  });

  test('tokens and passwords are not stored as they are', async () => {
    const rows = s.app.db.prepare('SELECT token_hash FROM sessions').all();
    assert.ok(rows.length > 0);
    assert.ok(rows.every((r) => !r.token_hash.includes(token) && r.token_hash.length === 64));
    const users = s.app.db.prepare('SELECT pass FROM users').all();
    assert.ok(users.every((u) => u.pass.startsWith('scrypt$') && !u.pass.includes('password')));
  });
});

describe('web', () => {
  test('answers the browser\'s preflight and unknown paths', async () => {
    const s = await start();
    const pre = await fetch(`http://127.0.0.1:${s.app.server.address().port}/api/data`, { method: 'OPTIONS' });
    assert.equal(pre.status, 204);
    assert.match(pre.headers.get('access-control-allow-headers'), /authorization/);
    assert.equal((await s.call('GET', '/nothing')).status, 404);
    assert.equal((await s.call('GET', '/api/nothing', undefined, undefined)).status, 401);
    await s.app.close();
  });
});
