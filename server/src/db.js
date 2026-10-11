// Storage: one SQLite file. Users, sessions (the hash of each token, never the token) and each user's synced
// values, one row per key with a revision number that only goes up.
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

export function openDb(dataDir) {
  const memory = dataDir === ':memory:'; // tests
  if (!memory) mkdirSync(dataDir, { recursive: true });
  const db = new DatabaseSync(memory ? ':memory:' : join(dataDir, 'streamboss-sync.db'));
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT NOT NULL UNIQUE,
      pass TEXT NOT NULL,
      created INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token_hash TEXT NOT NULL UNIQUE,
      device TEXT NOT NULL,
      created INTEGER NOT NULL,
      used INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS items (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      k TEXT NOT NULL,
      v TEXT,
      rev INTEGER NOT NULL,
      updated INTEGER NOT NULL,
      PRIMARY KEY (user_id, k)
    );
  `);
  return db;
}
