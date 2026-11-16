import { Injectable } from '@angular/core';

interface CacheRecord<T = unknown> {
  key: string;
  revision: string;
  data: T;
  updatedAt: number;
}

const DB_NAME = 'christian_app_release_cache';
const DB_VERSION = 1;
const STORE_NAME = 'assets';

@Injectable({ providedIn: 'root' })
export class IndexedDbCacheService {
  private dbPromise: Promise<IDBDatabase | null> | null = null;

  private openDb(): Promise<IDBDatabase | null> {
    if (typeof indexedDB === 'undefined') {
      return Promise.resolve(null);
    }
    if (this.dbPromise) {
      return this.dbPromise;
    }

    this.dbPromise = new Promise<IDBDatabase | null>((resolve) => {
      try {
        const req = indexedDB.open(DB_NAME, DB_VERSION);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains(STORE_NAME)) {
            db.createObjectStore(STORE_NAME, { keyPath: 'key' });
          }
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => resolve(null);
      } catch {
        resolve(null);
      }
    });

    return this.dbPromise;
  }

  async get<T>(key: string, expectedRevision: string): Promise<T | null> {
    const db = await this.openDb();
    if (!db) return null;

    return new Promise<T | null>((resolve) => {
      try {
        const tx = db.transaction(STORE_NAME, 'readonly');
        const store = tx.objectStore(STORE_NAME);
        const req = store.get(key);
        req.onsuccess = () => {
          const record = req.result as CacheRecord<T> | undefined;
          if (!record) {
            resolve(null);
            return;
          }
          if (expectedRevision && record.revision !== expectedRevision) {
            resolve(null);
            return;
          }
          resolve(record.data);
        };
        req.onerror = () => resolve(null);
      } catch {
        resolve(null);
      }
    });
  }

  async set<T>(key: string, data: T, revision: string): Promise<void> {
    const db = await this.openDb();
    if (!db) return;

    return new Promise<void>((resolve) => {
      try {
        const tx = db.transaction(STORE_NAME, 'readwrite');
        const store = tx.objectStore(STORE_NAME);
        const record: CacheRecord<T> = {
          key,
          revision,
          data,
          updatedAt: Date.now(),
        };
        store.put(record);
        tx.oncomplete = () => resolve();
        tx.onerror = () => resolve();
      } catch {
        resolve();
      }
    });
  }

  async clear(): Promise<void> {
    const db = await this.openDb();
    if (!db) return;

    return new Promise<void>((resolve) => {
      try {
        const tx = db.transaction(STORE_NAME, 'readwrite');
        tx.objectStore(STORE_NAME).clear();
        tx.oncomplete = () => resolve();
        tx.onerror = () => resolve();
      } catch {
        resolve();
      }
    });
  }
}
