const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");

const {
  COLLECTIONS,
  PURCHASE_JSON_LIMIT,
  createPurchaseInvoice,
  createPurchaseInvoiceCommandRouter,
  confirmPrices,
  confirmReceipt,
  postToAccounting,
  reviewProductTask,
} = require("../purchase-invoice-commands");
const {safeJsonErrorHandler} = require("../inter-branch-invoice-commands");
const {FakeFirestore, fakeAdmin} = require("./support/fake-firestore");

const now = new Date("2026-08-03T10:00:00.000Z");

function seed() {
  return {
    users: {
      collector: {name: "المدير العام", role: "collector", isActive: true, mustChangePassword: false},
      accountant: {name: "المحاسب", role: "accountant", isActive: true, mustChangePassword: false},
      "manager-r": {
        name: "مدير الفرع المستلم",
        role: "manager",
        branchId: "branch-r",
        isActive: true,
        mustChangePassword: false,
      },
      "manager-x": {
        name: "مدير فرع آخر",
        role: "manager",
        branchId: "branch-x",
        isActive: true,
        mustChangePassword: false,
      },
      inactive: {name: "موقوف", role: "collector", isActive: false, mustChangePassword: false},
      forced: {name: "تغيير كلمة مرور", role: "collector", isActive: true, mustChangePassword: true},
    },
    branches: {
      "branch-r": {
        id: "branch-r",
        name: "الفرع المستلم",
        brand_id: "brand-r",
        branch_manager_id: "manager-r",
      },
      "branch-x": {
        id: "branch-x",
        name: "فرع آخر",
        brand_id: "brand-x",
        branch_manager_id: "manager-x",
      },
    },
    brands: {
      "brand-r": {id: "brand-r", name: "العلامة المستلمة"},
      "brand-x": {id: "brand-x", name: "علامة أخرى"},
    },
    product_groups: {
      "group-r": {id: "group-r", brand_id: "brand-r", name: "مجموعة", active: true},
      "group-x": {id: "group-x", brand_id: "brand-x", name: "أخرى", active: true},
    },
    products: {
      "product-r": {
        id: "product-r",
        brand_id: "brand-r",
        group_id: "group-r",
        name: "مادة الكتالوج",
        active: true,
        version: 1,
        units: [{unit_id: "primary", display_value: "حبة", raw_value: "حبه"}],
      },
      "product-r-2": {
        id: "product-r-2",
        brand_id: "brand-r",
        group_id: "group-r",
        name: "مادة مطابقة",
        active: true,
        version: 2,
        units: [{unit_id: "box", display_value: "علبة", raw_value: "علبة"}],
      },
      "product-x": {
        id: "product-x",
        brand_id: "brand-x",
        group_id: "group-x",
        name: "مادة علامة أخرى",
        active: true,
        version: 1,
        units: [{unit_id: "primary", display_value: "حبة", raw_value: "حبة"}],
      },
    },
  };
}

function createPayload() {
  return {
    receiving_branch_id: "branch-r",
    currency: "YER",
    supplier_name: "مورد أول",
    supplier_invoice_number: "S-100",
    supplier_invoice_date: "2026-08-03",
    general_manager_notes: "ملاحظة عامة بلا أسعار",
    items: [
      {
        source_type: "catalog",
        product_id: "product-r",
        unit_id: "primary",
        ordered_quantity: 5,
        provisional_unit_price: 9,
      },
      {
        source_type: "unmatched",
        material_name: "مادة غير مطابقة",
        group_text: "",
        unit_text: "علبة",
        ordered_quantity: 3,
      },
    ],
  };
}

function uuidFactory() {
  let value = 0;
  return () => `generated-${String(++value).padStart(4, "0")}`;
}

async function createInvoice(firestore, key = "create-0001") {
  const randomUUID = uuidFactory();
  const result = await createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: createPayload(),
    idempotencyKey: key,
    timestamp: now,
    randomUUID,
  });
  return {result, randomUUID};
}

function publicItems(firestore, invoiceId) {
  return firestore.documents(`purchase_invoices/${invoiceId}/items`)
      .sort((left, right) => left.line_number - right.line_number);
}

function findTask(firestore, invoiceId) {
  return firestore.documents(COLLECTIONS.reviewTasks)
      .find((task) => task.invoice_id === invoiceId);
}

function fillUtf8Bytes(prefix, maximumBytes, character = "م") {
  const prefixBytes = Buffer.byteLength(prefix, "utf8");
  const characterBytes = Buffer.byteLength(character, "utf8");
  const count = Math.floor((maximumBytes - prefixBytes) / characterBytes);
  const remainder = maximumBytes - prefixBytes - (count * characterBytes);
  return `${prefix}${character.repeat(count)}${"x".repeat(remainder)}`;
}

test("collector creates an atomic scalable purchase invoice and unmatched task without public prices", async () => {
  const firestore = new FakeFirestore(seed());
  const {result} = await createInvoice(firestore);
  const invoiceId = result.responseData.invoice_id;
  const invoice = firestore.document(COLLECTIONS.invoices, invoiceId);
  const items = publicItems(firestore, invoiceId);
  const protectedPrice = firestore.document(COLLECTIONS.prices, invoiceId);
  const task = findTask(firestore, invoiceId);

  assert.equal(result.statusCode, 201);
  assert.equal(invoice.status, "pendingReceiverReview");
  assert.equal(invoice.item_count, 2);
  assert.equal(invoice.items, undefined);
  assert.equal(items.length, 2);
  assert.equal(items[0].canonical_product_id, "product-r");
  assert.equal(items[1].review_status, "pending_review");
  assert.equal(task.original_material_name, "مادة غير مطابقة");
  assert.equal(task.original_group_text, "");
  assert.deepEqual(protectedPrice.provisional_items, [{item_id: items[0].item_id, unit_price: 9}]);
  for (const value of [invoice, ...items, ...firestore.documents(COLLECTIONS.events)]) {
    assert.doesNotMatch(JSON.stringify(value), /unit_price|line_total|invoice_total|accounting_reference/);
  }
  const notificationText = JSON.stringify(firestore.documents(COLLECTIONS.notifications));
  assert.doesNotMatch(notificationText, /unit_price|line_total|invoice_total|accounting_reference|\b9\b/);
});

test("creation validates collector role, receiving brand ownership, duplicates, and idempotency", async () => {
  const firestore = new FakeFirestore(seed());
  const randomUUID = uuidFactory();
  await assert.rejects(() => createPurchaseInvoice({
    firestore,
    actorUid: "manager-r",
    payload: createPayload(),
    idempotencyKey: "wrong-role-1",
    timestamp: now,
    randomUUID,
  }), (error) => error.code === "forbidden");
  const wrongBrand = createPayload();
  wrongBrand.items[0] = {...wrongBrand.items[0], product_id: "product-x"};
  await assert.rejects(() => createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: wrongBrand,
    idempotencyKey: "wrong-brand-1",
    timestamp: now,
    randomUUID,
  }), (error) => error.code === "product-brand-mismatch");

  const first = await createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: createPayload(),
    idempotencyKey: "same-request-1",
    timestamp: now,
    randomUUID,
  });
  const replay = await createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: createPayload(),
    idempotencyKey: "same-request-1",
    timestamp: now,
    randomUUID,
  });
  assert.equal(replay.replay, true);
  assert.equal(replay.responseData.invoice_id, first.responseData.invoice_id);
  await assert.rejects(() => createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: {...createPayload(), supplier_invoice_number: "S-101"},
    idempotencyKey: "same-request-1",
    timestamp: now,
    randomUUID,
  }), (error) => error.code === "idempotency-conflict");
  await assert.rejects(() => createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: createPayload(),
    idempotencyKey: "duplicate-supplier-2",
    timestamp: now,
    randomUUID,
  }), (error) => error.code === "duplicate-supplier-invoice");
});

test("receipt remains non-blocking with unresolved review tasks and rejects cross-branch actors", async () => {
  const firestore = new FakeFirestore(seed());
  const {result} = await createInvoice(firestore);
  const invoiceId = result.responseData.invoice_id;
  const items = publicItems(firestore, invoiceId);
  const payload = {
    expected_revision: 1,
    receiver_notes: "تم الاستلام",
    items: items.map((item) => ({
      item_id: item.item_id,
      received_quantity: item.ordered_quantity,
      damaged_quantity: 0,
      missing_quantity: 0,
    })),
  };
  await assert.rejects(() => confirmReceipt({
    firestore,
    actorUid: "manager-x",
    invoiceId,
    payload,
    idempotencyKey: "cross-branch-1",
    timestamp: now,
  }), (error) => error.code === "forbidden");
  const receipt = await confirmReceipt({
    firestore,
    actorUid: "manager-r",
    invoiceId,
    payload,
    idempotencyKey: "receipt-0001",
    timestamp: now,
  });
  assert.equal(receipt.responseData.status, "pendingPriceEntry");
  assert.equal(findTask(firestore, invoiceId).status, "pending_review");
});

test("each workflow command fails closed for the wrong role or state", async () => {
  const firestore = new FakeFirestore(seed());
  const {result, randomUUID} = await createInvoice(firestore);
  const invoiceId = result.responseData.invoice_id;
  const items = publicItems(firestore, invoiceId);
  const receiptPayload = {
    expected_revision: 1,
    items: items.map((item) => ({
      item_id: item.item_id,
      received_quantity: item.ordered_quantity,
      damaged_quantity: 0,
      missing_quantity: 0,
    })),
  };
  const pricePayload = {
    expected_revision: 1,
    items: items.map((item) => ({item_id: item.item_id, unit_price: 1})),
  };
  const postingPayload = {
    expected_revision: 1,
    accounting_reference: "ACC-X",
    override_unresolved_materials: false,
  };
  const task = findTask(firestore, invoiceId);

  await assert.rejects(() => confirmReceipt({
    firestore, actorUid: "collector", invoiceId, payload: receiptPayload,
    idempotencyKey: "role-receipt-1", timestamp: now,
  }), (error) => error.code === "forbidden");
  await assert.rejects(() => confirmPrices({
    firestore, actorUid: "manager-r", invoiceId, payload: pricePayload,
    idempotencyKey: "role-price-1", timestamp: now,
  }), (error) => error.code === "forbidden");
  await assert.rejects(() => confirmPrices({
    firestore, actorUid: "collector", invoiceId, payload: pricePayload,
    idempotencyKey: "state-price-1", timestamp: now,
  }), (error) => error.code === "invalid-state");
  await assert.rejects(() => postToAccounting({
    firestore, actorUid: "collector", invoiceId, payload: postingPayload,
    idempotencyKey: "role-post-1", timestamp: now,
  }), (error) => error.code === "forbidden");
  await assert.rejects(() => postToAccounting({
    firestore, actorUid: "accountant", invoiceId, payload: postingPayload,
    idempotencyKey: "state-post-1", timestamp: now,
  }), (error) => error.code === "invalid-state");
  await assert.rejects(() => reviewProductTask({
    firestore,
    actorUid: "collector",
    taskId: task.id,
    payload: {
      expected_revision: 1,
      expected_invoice_revision: 1,
      action: "request_clarification",
      note: "اختبار",
    },
    idempotencyKey: "role-review-1",
    timestamp: now,
    randomUUID,
  }), (error) => error.code === "forbidden");
  for (const actorUid of ["inactive", "forced"]) {
    await assert.rejects(() => createPurchaseInvoice({
      firestore,
      actorUid,
      payload: createPayload(),
      idempotencyKey: `blocked-${actorUid}`,
      timestamp: now,
      randomUUID,
    }), (error) => error.code === "forbidden");
  }
});

test("full workflow blocks unresolved posting, supports audited override, and late reconciliation locks history", async () => {
  const firestore = new FakeFirestore(seed());
  const {result, randomUUID} = await createInvoice(firestore);
  const invoiceId = result.responseData.invoice_id;
  let items = publicItems(firestore, invoiceId);
  await confirmReceipt({
    firestore,
    actorUid: "manager-r",
    invoiceId,
    payload: {
      expected_revision: 1,
      items: items.map((item) => ({
        item_id: item.item_id,
        received_quantity: item.ordered_quantity,
        damaged_quantity: 0,
        missing_quantity: 0,
      })),
    },
    idempotencyKey: "receipt-full-1",
    timestamp: now,
  });
  items = publicItems(firestore, invoiceId);
  await confirmPrices({
    firestore,
    actorUid: "collector",
    invoiceId,
    payload: {
      expected_revision: 2,
      items: items.map((item, index) => ({item_id: item.item_id, unit_price: 10 + index})),
    },
    idempotencyKey: "prices-full-1",
    timestamp: now,
  });
  const posting = {
    expected_revision: 3,
    accounting_reference: "ACC-1",
    override_unresolved_materials: false,
  };
  await assert.rejects(() => postToAccounting({
    firestore,
    actorUid: "accountant",
    invoiceId,
    payload: posting,
    idempotencyKey: "post-blocked-1",
    timestamp: now,
  }), (error) => error.code === "unresolved-materials");
  await postToAccounting({
    firestore,
    actorUid: "accountant",
    invoiceId,
    payload: {
      ...posting,
      override_unresolved_materials: true,
      override_reason: "ضرورة إقفال الفترة مع متابعة المادة",
      accountant_notes: "ملاحظة محمية",
    },
    idempotencyKey: "post-override-1",
    timestamp: now,
  });
  const lockedBefore = firestore.document(COLLECTIONS.prices, invoiceId);
  assert.equal(lockedBefore.locked, true);
  assert.equal(lockedBefore.posting_override.used, true);
  assert.equal(firestore.document(COLLECTIONS.invoices, invoiceId).accounting_reference, undefined);
  assert.equal(firestore.document(COLLECTIONS.invoices, invoiceId).status, "postedToAccounting");

  const task = findTask(firestore, invoiceId);
  await reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: {
      expected_revision: 1,
      expected_invoice_revision: 4,
      action: "link_existing",
      product_id: "product-r-2",
      unit_id: "box",
    },
    idempotencyKey: "late-link-0001",
    timestamp: new Date("2026-08-04T10:00:00.000Z"),
    randomUUID,
  });
  const lockedAfter = firestore.document(COLLECTIONS.prices, invoiceId);
  assert.deepEqual(lockedAfter, lockedBefore);
  const reconciledTask = firestore.document(COLLECTIONS.reviewTasks, task.id);
  assert.equal(reconciledTask.status, "linked_material");
  assert.equal(reconciledTask.original_material_name, "مادة غير مطابقة");
  const reconciledItem = publicItems(firestore, invoiceId).find((item) => item.item_id === task.item_id);
  assert.equal(reconciledItem.original_material_name, "مادة غير مطابقة");
  assert.equal(reconciledItem.canonical_product_id, "product-r-2");
  assert.equal(firestore.documents(COLLECTIONS.priceHistory).length, 2);

  await reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: {
      expected_revision: 2,
      expected_invoice_revision: 5,
      action: "mark_synchronized",
      accounting_reference: "MAT-22",
    },
    idempotencyKey: "late-sync-0001",
    timestamp: new Date("2026-08-04T10:05:00.000Z"),
    randomUUID,
  });
  assert.equal(
      firestore.document(COLLECTIONS.reviewTasks, task.id).status,
      "synchronized",
  );
  assert.deepEqual(firestore.document(COLLECTIONS.prices, invoiceId), lockedBefore);
  assert.equal(firestore.documents(COLLECTIONS.priceHistory).length, 2);
});

test("review clarification cycle and concurrent revision checks are enforced", async () => {
  const firestore = new FakeFirestore(seed());
  const {result, randomUUID} = await createInvoice(firestore);
  const invoiceId = result.responseData.invoice_id;
  let task = findTask(firestore, invoiceId);
  await reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: {
      expected_revision: 1,
      expected_invoice_revision: 1,
      action: "request_clarification",
      note: "وضح الوحدة",
    },
    idempotencyKey: "clarify-0001",
    timestamp: now,
    randomUUID,
  });
  task = firestore.document(COLLECTIONS.reviewTasks, task.id);
  assert.equal(task.status, "clarification_requested");
  await reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: {
      expected_revision: 2,
      expected_invoice_revision: 2,
      action: "return_to_pending",
      note: "وصل التوضيح",
    },
    idempotencyKey: "clarify-return-1",
    timestamp: now,
    randomUUID,
  });
  task = firestore.document(COLLECTIONS.reviewTasks, task.id);
  assert.equal(task.status, "pending_review");

  const command = () => reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: {
      expected_revision: 3,
      expected_invoice_revision: 3,
      action: "link_existing",
      product_id: "product-r-2",
      unit_id: "box",
    },
    idempotencyKey: `concurrent-${Math.random()}`,
    timestamp: now,
    randomUUID,
  });
  const settled = await Promise.allSettled([command(), command()]);
  assert.equal(settled.filter((entry) => entry.status === "fulfilled").length, 1);
  assert.equal(settled.filter((entry) => entry.status === "rejected").length, 1);
});

test("accountant creates and synchronizes a catalog product with duplicate prevention", async () => {
  const firestore = new FakeFirestore(seed());
  const {result, randomUUID} = await createInvoice(firestore);
  const invoiceId = result.responseData.invoice_id;
  let task = findTask(firestore, invoiceId);
  const createDecision = {
    expected_revision: 1,
    expected_invoice_revision: 1,
    action: "create_product",
    material_name: "مادة جديدة معتمدة",
    legacy_code: "NEW-01",
    units: [
      {unit_id: "primary", display_value: "حبة", raw_value: "حبه"},
      {unit_id: "unit2", display_value: "علبة", raw_value: "علبة"},
      {unit_id: "unit3", display_value: "كرتون", raw_value: "كرتون"},
    ],
    primary_unit_id: "primary",
    accounting_reference: "MAT-NEW",
  };
  const created = await reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: createDecision,
    idempotencyKey: "create-catalog-1",
    timestamp: now,
    randomUUID,
  });
  const productId = created.responseData.product_id;
  const product = firestore.document(COLLECTIONS.products, productId);
  const group = firestore.document(
      COLLECTIONS.groups, `system-group-brand-r-uncategorized`,
  );
  task = firestore.document(COLLECTIONS.reviewTasks, task.id);
  assert.equal(product.name, "مادة جديدة معتمدة");
  assert.equal(product.units.length, 3);
  assert.equal(group.system_key, "uncategorized");
  assert.equal(task.status, "newly_created_material");
  assert.equal(task.original_material_name, "مادة غير مطابقة");
  assert.equal(task.canonical_product_id, productId);
  assert.equal(
      firestore.document(COLLECTIONS.accountingProfiles, productId).sync_state,
      "not_synced",
  );

  await reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: task.id,
    payload: {
      expected_revision: 2,
      expected_invoice_revision: 2,
      action: "mark_synchronized",
      accounting_reference: "MAT-NEW",
      sync_state: "synced",
    },
    idempotencyKey: "sync-created-1",
    timestamp: now,
    randomUUID,
  });
  assert.equal(
      firestore.document(COLLECTIONS.accountingProfiles, productId).sync_state,
      "synced",
  );
  assert.equal(
      firestore.document(COLLECTIONS.reviewTasks, task.id).status,
      "synchronized",
  );

  const secondPayload = createPayload();
  secondPayload.supplier_invoice_number = "S-200";
  const second = await createPurchaseInvoice({
    firestore,
    actorUid: "collector",
    payload: secondPayload,
    idempotencyKey: "create-second-1",
    timestamp: now,
    randomUUID,
  });
  const secondTask = findTask(firestore, second.responseData.invoice_id);
  await assert.rejects(() => reviewProductTask({
    firestore,
    actorUid: "accountant",
    taskId: secondTask.id,
    payload: createDecision,
    idempotencyKey: "duplicate-catalog-1",
    timestamp: now,
    randomUUID,
  }), (error) => error.code === "catalog-duplicate");
});

async function withServer(firestore, callback) {
  const app = express();
  app.use("/v1/purchase-invoices", express.json({limit: PURCHASE_JSON_LIMIT}));
  app.use(express.json({limit: "16kb"}));
  app.post("/test-global-json-limit", (_request, response) => response.status(204).end());
  app.use("/v1", createPurchaseInvoiceCommandRouter({
    admin: fakeAdmin(),
    firestore,
    now: () => now,
    randomUUID: uuidFactory(),
  }));
  app.use(safeJsonErrorHandler);
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await callback(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function post(base, path, body) {
  return fetch(`${base}${path}`, {
    method: "POST",
    headers: {
      authorization: "Bearer token-collector",
      "content-type": "application/json",
      "idempotency-key": "payload-boundary-1",
    },
    body: JSON.stringify(body),
  });
}

test("the purchase route accepts measured 50-item payloads over 16kb and returns safe 413 over 64kb", async () => {
  const data = seed();
  const receivingId = "b".repeat(128);
  data.branches[receivingId] = {
    id: receivingId,
    name: "فرع كبير",
    brand_id: "brand-r",
    branch_manager_id: "manager-r",
  };
  data.users["manager-r"].branchId = receivingId;
  const validBody = {
    receiving_branch_id: receivingId,
    currency: "YER",
    supplier_name: "م".repeat(150),
    supplier_invoice_number: "R".repeat(200),
    supplier_invoice_date: "2026-08-03",
    general_manager_notes: "م".repeat(500),
    items: Array.from({length: 50}, (_, index) => ({
      source_type: "unmatched",
      material_name: fillUtf8Bytes(`${index}-`, 400),
      group_text: "ج".repeat(150),
      unit_text: "و".repeat(50),
      ordered_quantity: 1_000_000_000_000_000,
      line_notes: "ن".repeat(100),
      provisional_unit_price: 1_000_000_000_000_000,
    })),
  };
  const validBytes = Buffer.byteLength(JSON.stringify(validBody), "utf8");
  assert.equal(validBytes, 60_393);
  const paddedBody = (targetBytes) => {
    const base = {...validBody, padding: ""};
    const baseBytes = Buffer.byteLength(JSON.stringify(base), "utf8");
    const paddingBytes = targetBytes - baseBytes;
    assert.ok(paddingBytes >= 0);
    const body = {...base, padding: "x".repeat(paddingBytes)};
    assert.equal(Buffer.byteLength(JSON.stringify(body), "utf8"), targetBytes);
    return body;
  };
  await withServer(new FakeFirestore(data), async (base) => {
    const accepted = await post(base, "/v1/purchase-invoices", validBody);
    assert.equal(accepted.status, 201);
    const globalRejected = await post(base, "/test-global-json-limit", validBody);
    assert.equal(globalRejected.status, 413);
    const atRouteLimit = await post(
        base, "/v1/purchase-invoices", paddedBody(64 * 1024),
    );
    assert.equal(atRouteLimit.status, 400);
    assert.equal((await atRouteLimit.json()).error.code, "invalid-argument");
    const oversized = await post(
        base, "/v1/purchase-invoices", paddedBody((64 * 1024) + 1),
    );
    assert.equal(oversized.status, 413);
    assert.deepEqual(await oversized.json(), {
      error: {code: "payload-too-large", message: "The JSON request exceeds the allowed size."},
    });
  });
});
