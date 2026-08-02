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

  collection(name) {
    return new FakeCollectionReference(this.firestore, `${this.path}/${name}`);
  }
}

class FakeQuery {
  constructor(firestore, collectionName, filters = [], orderBys = []) {
    this.firestore = firestore;
    this.collectionName = collectionName;
    this.filters = filters;
    this.orderBys = orderBys;
    this.kind = "query";
  }

  where(field, operator, value) {
    if (operator !== "==") throw new Error(`Unsupported fake query operator: ${operator}`);
    return new FakeQuery(
        this.firestore,
        this.collectionName,
        [...this.filters, {field, value}],
        this.orderBys,
    );
  }

  orderBy(field, direction = "asc") {
    if (direction !== "asc" && direction !== "desc") {
      throw new Error(`Unsupported fake ordering: ${direction}`);
    }
    return new FakeQuery(
        this.firestore,
        this.collectionName,
        this.filters,
        [...this.orderBys, {field, direction}],
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
    const matches = [];
    for (const [id, value] of this._collection(query.collectionName)) {
      if (query.filters.every((filter) => value?.[filter.field] === filter.value)) {
        matches.push({id, value});
      }
    }
    matches.sort((left, right) => {
      for (const order of query.orderBys) {
        const leftValue = left.value?.[order.field];
        const rightValue = right.value?.[order.field];
        const comparison = leftValue < rightValue ? -1 : leftValue > rightValue ? 1 : 0;
        if (comparison !== 0) return order.direction === "asc" ? comparison : -comparison;
      }
      return left.id.localeCompare(right.id);
    });
    const documents = matches.map(({id, value}) => {
      const reference = new FakeDocumentReference(this, query.collectionName, id);
      return new FakeDocumentSnapshot(reference, value);
    });
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
