const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");

const {
  createInterBranchInvoiceCommandRouter,
  INTER_BRANCH_JSON_LIMIT,
  safeJsonErrorHandler,
} = require("../inter-branch-invoice-commands");
const {
  deterministicDocumentId,
  productPriceLatestKey,
} = require("../inter-branch-invoice-domain");
const {FakeFirestore, fakeAdmin} = require("./support/fake-firestore");

const fixedNow = new Date("2026-08-02T12:00:00.000Z");

function seed({includeCounter = true} = {}) {
  return {
    users: {
      "manager-s": {
        name: "مدير المورد",
        role: "manager",
        branchId: "branch-s",
        isActive: true,
        mustChangePassword: false,
      },
      "manager-r": {
        name: "مدير المستلم",
        role: "manager",
        branchId: "branch-r",
        isActive: true,
        mustChangePassword: false,
      },
      collector: {
        name: "المدير العام",
        role: "collector",
        isActive: true,
        mustChangePassword: false,
      },
      accountant: {
        name: "المحاسب",
        role: "accountant",
        isActive: true,
        mustChangePassword: false,
      },
      admin: {
        name: "المسؤول",
        role: "admin",
        isActive: true,
        mustChangePassword: false,
      },
      "must-change": {
        name: "غير جاهز",
        role: "manager",
        branchId: "branch-s",
        isActive: true,
        mustChangePassword: true,
      },
      inactive: {
        name: "Inactive",
        role: "manager",
        branchId: "branch-s",
        isActive: false,
        mustChangePassword: false,
      },
      "unknown-role": {
        name: "Unknown role",
        role: "auditor",
        isActive: true,
        mustChangePassword: false,
      },
    },
    branches: {
      "branch-s": {
        id: "branch-s",
        name: "فرع المورد",
        brand_id: "brand-a",
        branch_code: "AA",
        branch_manager_id: "manager-s",
      },
      "branch-r": {
        id: "branch-r",
        name: "فرع المستلم",
        brand_id: "brand-b",
        branch_code: "BB",
        branch_manager_id: "manager-r",
      },
    },
    brands: {
      "brand-a": {id: "brand-a", name: "Brand A"},
      "brand-b": {id: "brand-b", name: "Brand B"},
    },
    product_groups: {
      "group-a": {
        id: "group-a",
        brand_id: "brand-a",
        name: "مجموعة أ",
        legacy_code: "GA",
        active: true,
      },
      "group-b": {
        id: "group-b",
        brand_id: "brand-b",
        name: "مجموعة ب",
        active: true,
      },
    },
    products: {
      "product-a": {
        id: "product-a",
        brand_id: "brand-a",
        group_id: "group-a",
        name: "منتج أ",
        legacy_code: "PA",
        active: true,
        version: 3,
        units: [{
          unit_id: "primary",
          display_value: "حبة",
          raw_value: "حبه",
        }],
      },
      "product-b": {
        id: "product-b",
        brand_id: "brand-b",
        group_id: "group-b",
        name: "منتج ب",
        active: true,
        version: 1,
        units: [{
          unit_id: "primary",
          display_value: "علبة",
          raw_value: "علبة",
        }],
      },
    },
    inter_branch_invoice_counters: includeCounter ? {
      "branch-s": {
        branch_id: "branch-s",
        branch_code: "AA",
        next_number: 1,
      },
    } : {},
  };
}

function seedWithCatalogItems(count) {
  const data = seed();
  data.products = {};
  for (let index = 1; index <= count; index += 1) {
    const id = `product-${String(index).padStart(2, "0")}`;
    data.products[id] = {
      id,
      brand_id: "brand-a",
      group_id: "group-a",
      name: `منتج ${index}`,
      legacy_code: `P${index}`,
      active: true,
      version: 1,
      units: [{
        unit_id: "primary",
        display_value: "حبة",
        raw_value: "حبه",
      }],
    };
  }
  return data;
}

function maximumFiftyItemCreationFixture() {
  const data = seed();
  const unitId = "u".repeat(64);
  const receivingBranchId = "b".repeat(128);
  data.branches[receivingBranchId] = {
    ...data.branches["branch-r"],
    id: receivingBranchId,
  };
  delete data.branches["branch-r"];
  data.users["manager-r"].branchId = receivingBranchId;
  data.products = {};
  const items = Array.from({length: 50}, (_, index) => {
    const suffix = String(index + 1).padStart(2, "0");
    const productId = `p${suffix}${"x".repeat(125)}`;
    data.products[productId] = {
      id: productId,
      brand_id: "brand-a",
      group_id: "group-a",
      name: `منتج حمولة ${index + 1}`,
      active: true,
      version: 1,
      units: [{
        unit_id: unitId,
        display_value: "حبة",
        raw_value: "حبه",
      }],
    };
    return {
      product_id: productId,
      unit_id: unitId,
      supplied_quantity: 1_000_000_000_000_000,
      line_notes: "ن".repeat(50),
    };
  });
  return {
    data,
    payload: {
      receiving_branch_id: receivingBranchId,
      invoice_notes: "ن".repeat(500),
      items,
    },
  };
}

async function withServer(firestore, callback) {
  let uuid = 0;
  const app = express();
  app.use(
      "/v1/inter-branch-invoices",
      express.json({limit: INTER_BRANCH_JSON_LIMIT}),
  );
  app.use(express.json({limit: "16kb"}));
  app.post("/test-global-json-limit", (_request, response) => {
    response.status(204).end();
  });
  app.use("/v1", createInterBranchInvoiceCommandRouter({
    admin: fakeAdmin(),
    firestore,
    now: () => fixedNow,
    randomUUID: () => `item-${String(++uuid).padStart(4, "0")}`,
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

function invoiceItems(firestore, invoiceId) {
  return firestore
      .documents(`inter_branch_invoices/${invoiceId}/items`)
      .sort((left, right) => left.line_number - right.line_number);
}

function post(baseUrl, path, {uid, key, body}) {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer token-${uid}`,
      "content-type": "application/json",
      "idempotency-key": key,
    },
    body: JSON.stringify(body),
  });
}

function publicHasProtectedKey(value) {
  if (Array.isArray(value)) return value.some(publicHasProtectedKey);
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(([key, nested]) =>
    /(?:^|_)(?:price|prices|total|cost|amount|currency|suggestion|suggested)(?:_|$)/i.test(key) ||
      publicHasProtectedKey(nested));
}

test("the complete direct workflow is atomic, idempotent, and price-isolated", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const createBody = {
      receiving_branch_id: "branch-r",
      invoice_notes: "تسليم مباشر",
      items: [{
        product_id: "product-a",
        unit_id: "primary",
        supplied_quantity: 10,
        line_notes: "عبوة سليمة",
      }],
    };
    let response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "create-flow-0001",
      body: createBody,
    });
    assert.equal(response.status, 201);
    const created = await response.json();
    assert.deepEqual(created, {
      invoice_id: created.invoice_id,
      invoice_number: "AA0001",
      status: "pendingReceiverReview",
      revision: 1,
    });
    assert.equal(firestore.documents("inter_branch_invoice_counters")[0].next_number, 2);
    let invoice = firestore.document("inter_branch_invoices", created.invoice_id);
    let items = invoiceItems(firestore, created.invoice_id);
    assert.equal(invoice.sending_brand_id, "brand-a");
    assert.equal(invoice.receiving_brand_id, "brand-b");
    assert.equal(invoice.item_count, 1);
    assert.equal(Object.hasOwn(invoice, "items"), false);
    assert.equal(items[0].product_name, "منتج أ");
    assert.equal(publicHasProtectedKey(invoice), false);
    assert.equal(publicHasProtectedKey(items), false);

    response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "create-flow-0001",
      body: createBody,
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).idempotent_replay, true);
    assert.equal(firestore.documents("inter_branch_invoices").length, 1);
    assert.equal(firestore.documents("inter_branch_invoice_counters")[0].next_number, 2);

    response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "create-flow-0001",
      body: {...createBody, invoice_notes: "طلب مختلف"},
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "idempotency-conflict");

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-s",
          key: "wrong-receiver-0001",
          body: {
            expected_revision: 1,
            items: [{item_id: items[0].item_id, received_quantity: 10}],
          },
        },
    );
    assert.equal(response.status, 403);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "stale-receipt-0001",
          body: {
            expected_revision: 99,
            items: [{item_id: items[0].item_id, received_quantity: 10}],
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "stale-revision");

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "receipt-flow-0001",
          body: {
            expected_revision: 1,
            receiver_notes: "تم العد",
            items: [{
              item_id: items[0].item_id,
              received_quantity: 8,
              damaged_quantity: 1,
              missing_quantity: 2,
              discrepancy_notes: "نقص وحدتين",
            }],
          },
        },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).status, "pendingPriceEntry");
    invoice = firestore.document("inter_branch_invoices", created.invoice_id);
    items = invoiceItems(firestore, created.invoice_id);
    assert.equal(items[0].received_quantity, 8);
    assert.equal(invoice.item_digest.length, 64);
    assert.equal(publicHasProtectedKey(invoice), false);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "receipt-flow-0001",
          body: {
            expected_revision: 1,
            receiver_notes: "تم العد",
            items: [{
              item_id: items[0].item_id,
              received_quantity: 8,
              damaged_quantity: 1,
              missing_quantity: 2,
              discrepancy_notes: "نقص وحدتين",
            }],
          },
        },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).idempotent_replay, true);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "receipt-new-key-0001",
          body: {
            expected_revision: 1,
            items: [{item_id: items[0].item_id, received_quantity: 8}],
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "invalid-state");

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-s",
          key: "wrong-receiver-state-0002",
          body: {
            expected_revision: 1,
            items: [{item_id: items[0].item_id, received_quantity: 8}],
          },
        },
    );
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, "forbidden");

    const latestKey = productPriceLatestKey({
      brandId: "brand-a",
      productId: "product-a",
      unitId: "primary",
      currency: "YER",
    });
    const previousLatest = {
      id: latestKey,
      latest_key: latestKey,
      history_event_id: "old-history",
      brand_id: "brand-a",
      product_id: "product-a",
      unit_id: "wrong-unit",
      unit_value: "legacy-unit-spelling",
      currency: "YER",
      price: 100,
      source_invoice_id: "old-invoice",
      version: 4,
    };
    firestore._collection("product_price_latest").set(latestKey, previousLatest);
    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "collector",
          key: "bad-memory-0001",
          body: {
            expected_revision: 2,
            currency: "YER",
            items: [{item_id: items[0].item_id, unit_price: 12.5}],
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "price-memory-conflict");
    assert.equal(
        firestore.document("inter_branch_invoices", created.invoice_id).status,
        "pendingPriceEntry",
    );
    assert.equal(firestore.documents("inter_branch_invoice_prices").length, 0);
    firestore._collection("product_price_latest").set(latestKey, {
      ...previousLatest,
      unit_id: "primary",
    });

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "admin",
          key: "admin-price-0001",
          body: {
            expected_revision: 2,
            currency: "YER",
            items: [{item_id: items[0].item_id, unit_price: 12.5}],
          },
        },
    );
    assert.equal(response.status, 403);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "accountant",
          key: "accountant-price-0001",
          body: {
            expected_revision: 2,
            currency: "YER",
            items: [{item_id: items[0].item_id, unit_price: 12.5}],
          },
        },
    );
    assert.equal(response.status, 403);

    const pricingBody = {
      expected_revision: 2,
      currency: "YER",
      pricing_notes: "ملاحظة مالية محمية",
      items: [{item_id: items[0].item_id, unit_price: 12.5}],
    };
    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "collector",
          key: "pricing-flow-0001",
          body: pricingBody,
        },
    );
    assert.equal(response.status, 200);
    const pricedResponse = await response.json();
    assert.equal(pricedResponse.status, "pendingAccountingEntry");
    assert.equal(publicHasProtectedKey(pricedResponse), false);
    invoice = firestore.document("inter_branch_invoices", created.invoice_id);
    assert.equal(publicHasProtectedKey(invoice), false);
    const protectedSnapshot = firestore.document(
        "inter_branch_invoice_prices",
        created.invoice_id,
    );
    assert.equal(protectedSnapshot.currency, "YER");
    assert.equal(protectedSnapshot.items[0].unit_price, 12.5);
    assert.equal(protectedSnapshot.item_digest, invoice.item_digest);
    assert.equal(protectedSnapshot.pricing_notes, "ملاحظة مالية محمية");
    assert.equal(firestore.documents("product_price_latest").length, 1);
    assert.equal(firestore.documents("product_price_history").length, 1);
    const latest = firestore.document("product_price_latest", latestKey);
    assert.equal(latest.version, 5);
    assert.equal(latest.unit_value, items[0].unit_value);
    const priceHistory = firestore.documents("product_price_history")[0];
    assert.equal(priceHistory.previous_price, 100);
    assert.equal(priceHistory.previous_source_invoice_id, "old-invoice");
    assert.equal(priceHistory.previous_unit_value, "legacy-unit-spelling");

    const financialCounts = {
      latestVersion: latest.version,
      history: firestore.documents("product_price_history").length,
      notifications: firestore.documents("notifications").length,
      events: firestore.documents("inter_branch_invoice_events").length,
    };
    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "collector",
          key: "pricing-flow-0001",
          body: pricingBody,
        },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).idempotent_replay, true);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "collector",
          key: "pricing-new-key-0001",
          body: pricingBody,
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "invalid-state");
    assert.equal(firestore.document("product_price_latest", latestKey).version,
        financialCounts.latestVersion);
    assert.equal(firestore.documents("product_price_history").length,
        financialCounts.history);
    assert.equal(firestore.documents("notifications").length,
        financialCounts.notifications);
    assert.equal(firestore.documents("inter_branch_invoice_events").length,
        financialCounts.events);

    const validSnapshot = firestore.document(
        "inter_branch_invoice_prices",
        created.invoice_id,
    );
    firestore._collection("inter_branch_invoice_prices").set(created.invoice_id, {
      ...validSnapshot,
      invoice_total: validSnapshot.invoice_total + 1,
    });
    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/post-accounting`,
        {
          uid: "accountant",
          key: "bad-total-0001",
          body: {
            expected_revision: 3,
            accounting_reference: "ACC-BAD-TOTAL",
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "price-snapshot-mismatch");
    assert.equal(
        firestore.document("inter_branch_invoices", created.invoice_id).status,
        "pendingAccountingEntry",
    );

    firestore._collection("inter_branch_invoice_prices").set(created.invoice_id, {
      ...validSnapshot,
      item_digest: "0".repeat(64),
    });
    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/post-accounting`,
        {
          uid: "accountant",
          key: "bad-snapshot-0001",
          body: {
            expected_revision: 3,
            accounting_reference: "ACC-BAD",
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "price-snapshot-mismatch");
    assert.equal(
        firestore.document("inter_branch_invoices", created.invoice_id).status,
        "pendingAccountingEntry",
    );
    firestore._collection("inter_branch_invoice_prices").set(
        created.invoice_id,
        validSnapshot,
    );

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/post-accounting`,
        {
          uid: "accountant",
          key: "posting-flow-0001",
          body: {
            expected_revision: 3,
            accounting_reference: "ACC-2026-1",
            accounting_notes: "ملاحظة ترحيل محمية",
          },
        },
    );
    assert.equal(response.status, 200);
    const postedResponse = await response.json();
    assert.deepEqual(postedResponse, {
      invoice_id: created.invoice_id,
      status: "postedToAccounting",
      revision: 4,
    });
    invoice = firestore.document("inter_branch_invoices", created.invoice_id);
    assert.equal(invoice.accounting_reference, "ACC-2026-1");
    assert.equal(invoice.accounting_notes, undefined);
    assert.equal(publicHasProtectedKey(invoice), false);
    const locked = firestore.document("inter_branch_invoice_prices", created.invoice_id);
    assert.equal(locked.locked, true);
    assert.equal(locked.locked_invoice_revision, 4);
    assert.equal(locked.accounting_notes, "ملاحظة ترحيل محمية");

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/post-accounting`,
        {
          uid: "accountant",
          key: "posting-flow-0001",
          body: {
            expected_revision: 3,
            accounting_reference: "ACC-2026-1",
            accounting_notes: "ملاحظة ترحيل محمية",
          },
        },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).idempotent_replay, true);

    const notifications = firestore.documents("notifications");
    assert.deepEqual(
        new Set(notifications.map((item) => item.notification_type)),
        new Set([
          "inter_branch_v2_direct_created",
          "inter_branch_v2_receipt_confirmed",
          "inter_branch_v2_prices_confirmed",
          "inter_branch_v2_accounting_posted",
        ]),
    );
    assert.equal(notifications.some(publicHasProtectedKey), false);
    assert.equal(firestore.documents("inter_branch_invoice_commands").length, 4);
    const events = firestore.documents("inter_branch_invoice_events")
        .sort((left, right) => left.revision - right.revision);
    assert.equal(events.length, 4);
    assert.deepEqual(events.map((event) => event.revision), [1, 2, 3, 4]);
    assert.deepEqual(events.map((event) => event.action), [
      "direct_invoice_created",
      "receipt_confirmed",
      "prices_confirmed",
      "posted_to_accounting",
    ]);
    for (const event of events) {
      assert.equal(event.id, deterministicDocumentId(
          "inter-branch-v2-event",
          created.invoice_id,
          String(event.revision),
          event.action,
      ));
      assert.equal(publicHasProtectedKey(event), false);
    }
  });
});

test("counter starting at one allocates the first v2 invoice as 0001", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "counter-starts-one-0001",
      body: {
        receiving_branch_id: "branch-r",
        items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
      },
    });
    assert.equal(response.status, 201);
    assert.equal((await response.json()).invoice_number, "AA0001");
  });
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 2);
});

test("v2 counters below one fail without allocating an invoice", async () => {
  const data = seed();
  data.inter_branch_invoice_counters["branch-s"].next_number = 0;
  const firestore = new FakeFirestore(data);
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "counter-zero-0001",
      body: {
        receiving_branch_id: "branch-r",
        items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
      },
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "counter-invalid");
  });
  assert.equal(firestore.documents("inter_branch_invoices").length, 0);
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 0);
});

test("unassigned managers and stale branch manager references fail closed", async () => {
  const payload = {
    receiving_branch_id: "branch-r",
    items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
  };
  const unassignedData = seed();
  unassignedData.users["manager-s"].branchId = null;
  const unassignedFirestore = new FakeFirestore(unassignedData);
  await withServer(unassignedFirestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s", key: "unassigned-manager-0001", body: payload,
    });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, "forbidden");
  });

  const staleData = seed();
  staleData.branches["branch-s"].branch_manager_id = "manager-r";
  const staleFirestore = new FakeFirestore(staleData);
  await withServer(staleFirestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s", key: "stale-manager-0001", body: payload,
    });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, "forbidden");
  });
});

test("the isolated parser accepts the measured worst-case valid 50-item creation", async () => {
  const fixture = maximumFiftyItemCreationFixture();
  const bytes = Buffer.byteLength(JSON.stringify(fixture.payload), "utf8");
  assert.equal(bytes, 19983);
  assert.equal(bytes > 16 * 1024, true);
  assert.equal((32 * 1024) - bytes, 12785);
  const firestore = new FakeFirestore(fixture.data);
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "maximum-payload-0001",
      body: fixture.payload,
    });
    assert.equal(response.status, 201);
    const created = await response.json();
    assert.equal(invoiceItems(firestore, created.invoice_id).length, 50);
  });
});

test("a 50-item invoice completes atomically through every version-2 transition", async () => {
  const firestore = new FakeFirestore(seedWithCatalogItems(50));
  await withServer(firestore, async (baseUrl) => {
    const createItems = Array.from({length: 50}, (_, index) => ({
      product_id: `product-${String(index + 1).padStart(2, "0")}`,
      unit_id: "primary",
      supplied_quantity: index + 1,
    }));
    let response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "fifty-create-0001",
      body: {receiving_branch_id: "branch-r", items: createItems},
    });
    assert.equal(response.status, 201);
    const created = await response.json();
    let invoice = firestore.document("inter_branch_invoices", created.invoice_id);
    let items = invoiceItems(firestore, created.invoice_id);
    assert.equal(invoice.item_count, 50);
    assert.equal(items.length, 50);
    assert.equal(Object.hasOwn(invoice, "items"), false);
    assert.equal(new Set(items.map((item) => item.item_id)).size, 50);
    assert.equal(new Set(items.map((item) => item.line_number)).size, 50);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "fifty-receipt-0001",
          body: {
            expected_revision: 1,
            items: items.map((item) => ({
              item_id: item.item_id,
              received_quantity: item.supplied_quantity,
            })),
          },
        },
    );
    assert.equal(response.status, 200);
    items = invoiceItems(firestore, created.invoice_id);
    assert.equal(items.every((item) => item.invoice_revision === 2), true);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-prices`,
        {
          uid: "collector",
          key: "fifty-price-0001",
          body: {
            expected_revision: 2,
            currency: "YER",
            items: items.map((item, index) => ({
              item_id: item.item_id,
              unit_price: index + 1,
            })),
          },
        },
    );
    assert.equal(response.status, 200);
    assert.equal(firestore.documents("product_price_latest").length, 50);
    assert.equal(firestore.documents("product_price_history").length, 50);
    const priceSnapshot = firestore.document(
        "inter_branch_invoice_prices",
        created.invoice_id,
    );
    assert.equal(priceSnapshot.item_count, 50);
    assert.equal(priceSnapshot.items.length, 50);

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/post-accounting`,
        {
          uid: "accountant",
          key: "fifty-post-0001",
          body: {
            expected_revision: 3,
            accounting_reference: "ACC-50-ITEMS",
          },
        },
    );
    assert.equal(response.status, 200);
    invoice = firestore.document("inter_branch_invoices", created.invoice_id);
    assert.equal(invoice.status, "postedToAccounting");
    assert.equal(
        firestore.document("inter_branch_invoice_prices", created.invoice_id).locked,
        true,
    );
  });
});

test("an uninitialized counter fails without allocating an invoice", async () => {
  const firestore = new FakeFirestore(seed({includeCounter: false}));
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "missing-counter-0001",
      body: {
        receiving_branch_id: "branch-r",
        items: [{
          product_id: "product-a",
          unit_id: "primary",
          supplied_quantity: 1,
        }],
      },
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "counter-uninitialized");
  });
  assert.equal(firestore.documents("inter_branch_invoices").length, 0);
  assert.equal(firestore.documents("inter_branch_invoice_commands").length, 0);
  assert.equal(firestore.documents("notifications").length, 0);
});

test("spoofed identity fields and same-branch selection are rejected", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "spoofed-identity-0001",
      body: {
        sending_branch_id: "branch-r",
        created_by: "manager-r",
        receiving_branch_id: "branch-r",
        items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
      },
    });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.code, "invalid-argument");

    const sameBranchResponse = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "same-branch-0001",
      body: {
        receiving_branch_id: "branch-s",
        items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
      },
    });
    assert.equal(sameBranchResponse.status, 400);
    assert.equal((await sameBranchResponse.json()).error.code, "same-branch");
  });
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 1);
  assert.equal(firestore.documents("inter_branch_invoices").length, 0);
});

test("supplying-brand catalog enforcement does not consume the counter", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "wrong-brand-0001",
      body: {
        receiving_branch_id: "branch-r",
        items: [{
          product_id: "product-b",
          unit_id: "primary",
          supplied_quantity: 1,
        }],
      },
    });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, "product-brand-mismatch");
  });
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 1);
  assert.equal(firestore.documents("inter_branch_invoices").length, 0);
});

test("invalid catalog units and inactive products fail without consuming the counter", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const baseBody = {
      receiving_branch_id: "branch-r",
      items: [{product_id: "product-a", unit_id: "missing", supplied_quantity: 1}],
    };
    let response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "invalid-unit-0001",
      body: baseBody,
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "unit-invalid");

    const product = firestore.document("products", "product-a");
    firestore._collection("products").set("product-a", {
      ...product,
      name: "م".repeat(401),
    });
    response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "oversized-catalog-snapshot-0001",
      body: {...baseBody, items: [{...baseBody.items[0], unit_id: "primary"}]},
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "catalog-snapshot-invalid");

    firestore._collection("products").set("product-a", {...product, active: false});
    response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "inactive-product-0001",
      body: {...baseBody, items: [{...baseBody.items[0], unit_id: "primary"}]},
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "product-inactive");
  });
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 1);
  assert.equal(firestore.documents("inter_branch_invoices").length, 0);
  assert.equal(firestore.documents("inter_branch_invoice_events").length, 0);
});

test("an inactive assigned receiving manager cannot be replaced implicitly", async () => {
  const data = seed();
  data.users["manager-r"].isActive = false;
  data.users["manager-r-fallback"] = {
    name: "Fallback manager",
    role: "manager",
    branchId: "branch-r",
    isActive: true,
    mustChangePassword: false,
  };
  const firestore = new FakeFirestore(data);
  await withServer(firestore, async (baseUrl) => {
    const response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "inactive-receiver-0001",
      body: {
        receiving_branch_id: "branch-r",
        items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
      },
    });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "receiving-manager-not-configured");
  });
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 1);
  assert.equal(firestore.documents("inter_branch_invoices").length, 0);
});

test("inactive, must-change-password, unknown-role, and invalid-token users are denied", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const body = {
      receiving_branch_id: "branch-r",
      items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
    };
    let response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "must-change",
      key: "must-change-0001",
      body,
    });
    assert.equal(response.status, 403);
    response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "inactive",
      key: "inactive-user-0001",
      body,
    });
    assert.equal(response.status, 403);
    response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "unknown-role",
      key: "unknown-role-0001",
      body,
    });
    assert.equal(response.status, 403);
    response = await fetch(`${baseUrl}/v1/inter-branch-invoices`, {
      method: "POST",
      headers: {
        authorization: "Bearer invalid",
        "content-type": "application/json",
        "idempotency-key": "invalid-auth-0001",
      },
      body: JSON.stringify(body),
    });
    assert.equal(response.status, 401);
  });
});

test("a price-polluted public invoice fails closed before receipt", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    let response = await post(baseUrl, "/v1/inter-branch-invoices", {
      uid: "manager-s",
      key: "polluted-create-0001",
      body: {
        receiving_branch_id: "branch-r",
        items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
      },
    });
    assert.equal(response.status, 201);
    const created = await response.json();
    const item = invoiceItems(firestore, created.invoice_id)[0];
    const itemCollection = `inter_branch_invoices/${created.invoice_id}/items`;
    firestore._collection(itemCollection).set(item.item_id, {...item, unit_price: 42});

    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "polluted-receipt-0001",
          body: {
            expected_revision: 1,
            items: [{item_id: item.item_id, received_quantity: 1}],
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "public-price-field-forbidden");

    firestore._collection(itemCollection).set(item.item_id, {
      ...item,
      unexpected_snapshot: "not-supported",
    });
    response = await post(
        baseUrl,
        `/v1/inter-branch-invoices/${created.invoice_id}/confirm-receipt`,
        {
          uid: "manager-r",
          key: "polluted-extra-0001",
          body: {
            expected_revision: 1,
            items: [{item_id: item.item_id, received_quantity: 1}],
          },
        },
    );
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, "invoice-item-malformed");
  });
  assert.equal(firestore.documents("inter_branch_invoice_commands").length, 1);
  assert.equal(firestore.documents("inter_branch_invoice_events").length, 1);
});

test("concurrent creation commands allocate distinct counter values", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const body = {
      receiving_branch_id: "branch-r",
      items: [{product_id: "product-a", unit_id: "primary", supplied_quantity: 1}],
    };
    const responses = await Promise.all([
      post(baseUrl, "/v1/inter-branch-invoices", {
        uid: "manager-s",
        key: "concurrent-create-0001",
        body,
      }),
      post(baseUrl, "/v1/inter-branch-invoices", {
        uid: "manager-s",
        key: "concurrent-create-0002",
        body,
      }),
    ]);
    assert.deepEqual(responses.map((response) => response.status), [201, 201]);
    const results = await Promise.all(responses.map((response) => response.json()));
    assert.deepEqual(
        new Set(results.map((result) => result.invoice_number)),
        new Set(["AA0001", "AA0002"]),
    );
  });
  assert.equal(firestore.document("inter_branch_invoice_counters", "branch-s").next_number, 3);
});

test("malformed and oversized JSON receive sanitized JSON errors", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    let response = await fetch(`${baseUrl}/v1/inter-branch-invoices`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: "{",
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {
      error: {code: "invalid-json", message: "The JSON request is invalid."},
    });

    response = await fetch(`${baseUrl}/v1/inter-branch-invoices`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({padding: "x".repeat(33 * 1024)}),
    });
    assert.equal(response.status, 413);
    assert.deepEqual(await response.json(), {
      error: {
        code: "payload-too-large",
        message: "The JSON request exceeds the allowed size.",
      },
    });

    response = await fetch(`${baseUrl}/test-global-json-limit`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({padding: "x".repeat(17 * 1024)}),
    });
    assert.equal(response.status, 413);
    assert.equal((await response.json()).error.code, "payload-too-large");
  });
});
