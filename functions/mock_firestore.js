"use strict";

/**
 * Minimal in-memory Firestore mock for backend unit tests.
 *
 * Supports the operations used by routing_service / routes_callables:
 * - collection(path).doc(id).get() / set / update / delete
 * - collection(path).where(...).orderBy(...).limit(...).get()
 * - db.runTransaction with get / set / update / delete
 *
 * Plain Date objects are stored and returned as-is; the service reads them via
 * `?.toDate?.()` which tolerates plain Dates.
 */

function toKey(path) {
  return path.map((segment) => String(segment)).join("/");
}

class MockSnapshot {
  constructor(ref, data) {
    this.ref = ref;
    this._data = data;
  }
  get exists() {
    return this._data !== undefined && this._data !== null;
  }
  get id() {
    return this.ref.id;
  }
  data() {
    return this._data;
  }
}

class MockDocumentReference {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path[path.length - 1];
  }
  collection(name) {
    return new MockCollection(this.db, [...this.path, name]);
  }
  async get() {
    return this.db._snapshot(this.path);
  }
  async set(data, options) {
    this.db._write(this.path, data, options);
  }
  async update(data) {
    this.db._patch(this.path, data);
  }
  async delete() {
    this.db._delete(this.path);
  }
}

class MockQuery {
  constructor(collection, clauses = []) {
    this.collection = collection;
    this.db = collection.db;
    this.clauses = clauses;
  }
  where(field, op, value) {
    return new MockQuery(this.collection, [
      ...this.clauses,
      { type: "where", field, op, value },
    ]);
  }
  orderBy(field, direction) {
    return new MockQuery(this.collection, [
      ...this.clauses,
      { type: "orderBy", field, direction },
    ]);
  }
  limit(value) {
    return new MockQuery(this.collection, [
      ...this.clauses,
      { type: "limit", value },
    ]);
  }
  async get() {
    const prefix = this.collection.path.join("/") + "/";
    let docs = [];
    for (const [key, data] of this.db._entries()) {
      if (!key.startsWith(prefix)) continue;
      const rest = key.slice(prefix.length);
      if (rest.includes("/")) continue;
      docs.push(new MockSnapshot(new MockDocumentReference(this.db, [...this.collection.path, rest]), data));
    }
    for (const clause of this.clauses) {
      if (clause.type === "where") {
        docs = docs.filter((snap) => {
          const value = snap.data()?.[clause.field];
          switch (clause.op) {
            case "==":
              return value === clause.value;
            case "in":
              return Array.isArray(clause.value) && clause.value.includes(value);
            case "array-contains":
              return Array.isArray(value) && value.includes(clause.value);
            case ">":
              return value > clause.value;
            case ">=":
              return value >= clause.value;
            case "<":
              return value < clause.value;
            case "<=":
              return value <= clause.value;
            default:
              return false;
          }
        });
      } else if (clause.type === "orderBy") {
        const descending = String(clause.direction || "asc").toLowerCase() === "desc";
        docs.sort((a, b) => {
          const av = a.data()?.[clause.field];
          const bv = b.data()?.[clause.field];
          const at = av?.toDate?.() ?? av;
          const bt = bv?.toDate?.() ?? bv;
          const ta = at instanceof Date ? at.getTime() : at;
          const tb = bt instanceof Date ? bt.getTime() : bt;
          return descending ? tb - ta : ta - tb;
        });
      } else if (clause.type === "limit") {
        docs = docs.slice(0, clause.value);
      }
    }
    return {
      docs,
      size: docs.length,
      empty: docs.length === 0,
      forEach: (cb) => docs.forEach(cb),
    };
  }
}

class MockCollection {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  doc(id = null) {
    const resolved = id || `doc_${this.db._sequence++}`;
    return new MockDocumentReference(this.db, [...this.path, resolved]);
  }
  where(field, op, value) {
    return new MockQuery(this, [{ type: "where", field, op, value }]);
  }
  orderBy(field, direction) {
    return new MockQuery(this, [{ type: "orderBy", field, direction }]);
  }
  limit(value) {
    return new MockQuery(this, [{ type: "limit", value }]);
  }
  async get() {
    return new MockQuery(this).get();
  }
  async add(data) {
    const ref = this.doc();
    await ref.set(data);
    return ref;
  }
}

class MockTransaction {
  constructor(db) {
    this.db = db;
    this.pending = new Map();
  }
  async get(ref) {
    const key = toKey(ref.path);
    const data = this.pending.has(key)
      ? this.pending.get(key)
      : this.db._store.get(key);
    return new MockSnapshot(ref, data);
  }
  set(ref, data) {
    this.pending.set(toKey(ref.path), structuredClone(data));
  }
  update(ref, data) {
    const key = toKey(ref.path);
    const current = this.pending.has(key)
      ? this.pending.get(key)
      : this.db._store.get(key);
    this.pending.set(key, { ...current, ...structuredClone(data) });
  }
  delete(ref) {
    this.pending.set(toKey(ref.path), undefined);
  }
}

class MockFirestore {
  constructor() {
    this._store = new Map();
    this._sequence = 1;
  }
  collection(name) {
    return new MockCollection(this, [name]);
  }
  async runTransaction(fn) {
    const txn = new MockTransaction(this);
    const result = await fn(txn);
    for (const [key, value] of txn.pending) {
      if (value === undefined) {
        this._store.delete(key);
      } else {
        this._store.set(key, value);
      }
    }
    return result;
  }
  _snapshot(path) {
    const ref = new MockDocumentReference(this, path);
    return new MockSnapshot(ref, this._store.get(toKey(path)));
  }
  _write(path, data, options) {
    const key = toKey(path);
    if (options?.merge && this._store.has(key)) {
      this._store.set(key, {
        ...structuredClone(this._store.get(key)),
        ...structuredClone(data),
      });
    } else {
      this._store.set(key, structuredClone(data));
    }
  }
  _patch(path, data) {
    const key = toKey(path);
    const current = this._store.get(key) || {};
    this._store.set(key, { ...current, ...structuredClone(data) });
  }
  _delete(path) {
    this._store.delete(toKey(path));
  }
  _entries() {
    return [...this._store.entries()];
  }
  dump(path) {
    return this._store.get(path.join("/"));
  }
}

module.exports = { MockFirestore };
