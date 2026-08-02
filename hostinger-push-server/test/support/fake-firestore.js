function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

class FakeDocumentSnapshot {
  constructor(reference, value) {
    this.ref = reference;
    this.id = reference.id;
    this.exists = value !== undefined;
    this._value = clone(value);
  }

  data() {
    return clone(this._value);
  }
}

class FakeDocumentReference {
  constructor(firestore, collectionName, id) {
    this.firestore = firestore;
    this.collectionName = collectionName;
    this.id = id;
    this.path = `${collectionName}/${id}`;
    this.kind = "document";
  }

  get() {
    return Promise.resolve(this.firestore._snapshot(this));
  }
}

class FakeQuery {
  constructor(firestore, collectionName, filters = []) {
    this.firestore = firestore;
    this.collectionName = collectionName;
    this.filters = filters;
    this.kind = "query";
  }

  where(field, operator, value) {
    if (operator !== "==") throw new Error(`Unsupported fake query operator: ${operator}`);
    return new FakeQuery(
        this.firestore,
        this.collectionName,
        [...this.filters, {field, value}],
    );
  }
}

class FakeCollectionReference extends FakeQuery {
  doc(id) {
    const documentId = id || `auto-${String(++this.firestore.autoId).padStart(6, "0")}`;
    return new FakeDocumentReference(this.firestore, this.collectionName, documentId);
  }
}

class FakeTransaction {
  constructor(firestore) {
    this.firestore = firestore;
    this.operations = [];
  }

  async get(referenceOrQuery) {
    if (referenceOrQuery.kind === "document") {
      return this.firestore._snapshot(referenceOrQuery);
    }
    if (referenceOrQuery.kind === "query") {
      return this.firestore._querySnapshot(referenceOrQuery);
    }
    throw new Error("Unsupported fake Firestore read.");
  }

  set(reference, value, options) {
    this.operations.push({type: "set", reference, value: clone(value), options});
  }

  update(reference, value) {
    this.operations.push({type: "update", reference, value: clone(value)});
  }

  commit() {
    for (const operation of this.operations) {
      const collection = this.firestore._collection(operation.reference.collectionName);
      const current = collection.get(operation.reference.id);
      if (operation.type === "update" && current === undefined) {
        throw new Error(`Missing document for update: ${operation.reference.path}`);
      }
      if (operation.type === "set" && operation.options?.merge && current !== undefined) {
        collection.set(operation.reference.id, {...clone(current), ...clone(operation.value)});
      } else if (operation.type === "set") {
        collection.set(operation.reference.id, clone(operation.value));
      } else {
        collection.set(operation.reference.id, {...clone(current), ...clone(operation.value)});
      }
    }
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.collections = new Map();
    this.autoId = 0;
    this.transactionTail = Promise.resolve();
    for (const [collectionName, documents] of Object.entries(seed)) {
      const collection = this._collection(collectionName);
      for (const [id, value] of Object.entries(documents)) {
        collection.set(id, clone(value));
      }
    }
  }

  collection(name) {
    return new FakeCollectionReference(this, name);
  }

  runTransaction(callback) {
    const run = this.transactionTail.then(async () => {
      const transaction = new FakeTransaction(this);
      const result = await callback(transaction);
      transaction.commit();
      return result;
    });
    this.transactionTail = run.catch(() => undefined);
    return run;
  }

  document(collectionName, id) {
    return clone(this._collection(collectionName).get(id));
  }

  documents(collectionName) {
    return [...this._collection(collectionName).entries()].map(([id, value]) => ({
      id,
      ...clone(value),
    }));
  }

  _collection(name) {
    if (!this.collections.has(name)) this.collections.set(name, new Map());
    return this.collections.get(name);
  }

  _snapshot(reference) {
    return new FakeDocumentSnapshot(
        reference,
        this._collection(reference.collectionName).get(reference.id),
    );
  }

  _querySnapshot(query) {
    const documents = [];
    for (const [id, value] of this._collection(query.collectionName)) {
      if (query.filters.every((filter) => value?.[filter.field] === filter.value)) {
        const reference = new FakeDocumentReference(this, query.collectionName, id);
        documents.push(new FakeDocumentSnapshot(reference, value));
      }
    }
    return {docs: documents, empty: documents.length === 0, size: documents.length};
  }
}

function fakeAdmin() {
  return {
    auth: () => ({
      verifyIdToken: async (token) => {
        if (!token.startsWith("token-")) throw new Error("Invalid token");
        return {uid: token.slice("token-".length)};
      },
    }),
    firestore: {
      Timestamp: {
        fromDate: (date) => new Date(date),
      },
    },
  };
}

module.exports = {FakeFirestore, fakeAdmin};
