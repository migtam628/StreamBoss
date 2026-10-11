// Passwords are hashed with scrypt and a salt of their own; tokens are random and only their SHA-256 is stored,
// so a copy of the database cannot be used to sign in.
import { scrypt, randomBytes, timingSafeEqual, createHash } from 'node:crypto';

const N = 32768, R = 8, P = 1, KEYLEN = 32;

function derive(password, salt, n = N, r = R, p = P) {
  return new Promise((resolve, reject) => {
    scrypt(password.normalize('NFKC'), salt, KEYLEN, { N: n, r, p, maxmem: 128 * n * r * 2 }, (err, key) => (err ? reject(err) : resolve(key)));
  });
}

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const key = await derive(password, salt);
  return `scrypt$${N}$${R}$${P}$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password, stored) {
  const [alg, n, r, p, salt, key] = stored.split('$');
  if (alg !== 'scrypt') return false;
  const want = Buffer.from(key, 'base64');
  const got = await derive(password, Buffer.from(salt, 'base64'), +n, +r, +p);
  return want.length === got.length && timingSafeEqual(want, got);
}

// Used when the e-mail is unknown, so a wrong address takes as long to refuse as a wrong password.
let dummy;
export async function spendTime(password) {
  dummy ??= await hashPassword('not a real password');
  await verifyPassword(password, dummy);
}

export function newToken() {
  return randomBytes(32).toString('base64url');
}

export function tokenHash(token) {
  return createHash('sha256').update(token).digest('hex');
}

export const MIN_PASSWORD = 8;

export function normalizeEmail(email) {
  const e = String(email ?? '').trim().toLowerCase();
  return e.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e) ? e : null;
}
