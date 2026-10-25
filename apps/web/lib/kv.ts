/**
 * A tiny key-value store on IndexedDB, for the offline copy of groups and the queue of changes.
 * Falls back to memory when IndexedDB is missing or blocked (private windows), so the app still works.
 */
const DB = 'nussnuss';
const STORE = 'kv';
const memory = new Map<string, unknown>();
let opening: Promise<IDBDatabase | null> | null = null;

function open(): Promise<IDBDatabase | null> {
  if (opening) return opening;
  opening = new Promise((resolve) => {
    try {
      if (typeof indexedDB === 'undefined') return resolve(null);
      const req = indexedDB.open(DB, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
      req.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return opening;
}

function run<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T | undefined> {
  return open().then(
    (db) =>
      new Promise<T | undefined>((resolve) => {
        if (!db) return resolve(undefined);
        try {
          const req = fn(db.transaction(STORE, mode).objectStore(STORE));
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => resolve(undefined);
        } catch {
          resolve(undefined);
        }
      }),
  );
}

export async function kvGet<T>(key: string): Promise<T | undefined> {
  const v = await run<T>('readonly', (s) => s.get(key) as IDBRequest<T>);
  return v === undefined ? (memory.get(key) as T | undefined) : v;
}

export async function kvSet(key: string, value: unknown): Promise<void> {
  memory.set(key, value);
  await run('readwrite', (s) => s.put(value, key));
}

export async function kvDel(key: string): Promise<void> {
  memory.delete(key);
  await run('readwrite', (s) => s.delete(key));
}

/** Forget everything (signing out, deleting the account). */
export async function kvClear(): Promise<void> {
  memory.clear();
  await run('readwrite', (s) => s.clear());
}
