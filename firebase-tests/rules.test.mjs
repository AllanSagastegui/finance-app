import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import { ref, uploadBytes } from "firebase/storage";

const here = path.dirname(fileURLToPath(import.meta.url));
let env;

const validAccount = {
  name: "Efectivo",
  type: "cash",
  currencyCode: "PEN",
  initialBalanceMinor: 10000,
  currentBalanceMinor: 10000,
  archived: false,
  schemaVersion: 1,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
};

const validTransaction = {
  type: "expense",
  amountMinor: 1250,
  currencyCode: "PEN",
  accountId: "cash",
  destinationAccountId: null,
  categoryId: "other",
  description: "Almuerzo",
  occurredAt: new Date("2026-09-29T12:00:00Z"),
  status: "posted",
  schemaVersion: 1,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-aurea",
    firestore: {
      rules: fs.readFileSync(path.join(here, "../firestore.rules"), "utf8"),
    },
    storage: {
      rules: fs.readFileSync(path.join(here, "../storage.rules"), "utf8"),
    },
  });
});

after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

describe("Firestore owner isolation", () => {
  it("denies unauthenticated reads", async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "users/alice/accounts/cash")));
  });

  it("allows an owner to create a valid account", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/accounts/cash"), validAccount),
    );
  });

  it("denies cross-user writes", async () => {
    const db = env.authenticatedContext("mallory").firestore();
    await assertFails(
      setDoc(doc(db, "users/alice/accounts/cash"), validAccount),
    );
  });

  it("allows valid money documents and rejects negative amounts", async () => {
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      setDoc(doc(db, "users/alice/transactions/tx-good"), validTransaction),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/transactions/tx-bad"), {
        ...validTransaction,
        amountMinor: -1,
      }),
    );
  });

  it("protects server-owned balances and summaries", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "users/alice/accounts/cash"),
        validAccount,
      );
    });
    const db = env.authenticatedContext("alice").firestore();
    await assertFails(
      updateDoc(doc(db, "users/alice/accounts/cash"), {
        currentBalanceMinor: 99999999,
      }),
    );
    await assertFails(
      setDoc(doc(db, "users/alice/monthlySummaries/2026-09"), {
        netMinor: 99999999,
      }),
    );
  });

  it("allows account metadata edits but protects currency", async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), "users/alice/accounts/cash"),
        validAccount,
      );
    });
    const db = env.authenticatedContext("alice").firestore();
    await assertSucceeds(
      updateDoc(doc(db, "users/alice/accounts/cash"), {
        name: "Efectivo diario",
        type: "wallet",
        archived: true,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db, "users/alice/accounts/cash"), {
        currencyCode: "USD",
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe("Storage owner isolation", () => {
  it("allows an owner receipt with safe metadata", async () => {
    const storage = env.authenticatedContext("alice").storage();
    const result = await assertSucceeds(
      uploadBytes(
        ref(storage, "users/alice/receipts/tx-1/receipt.jpg"),
        new Uint8Array([1, 2, 3]),
        { contentType: "image/jpeg", customMetadata: { ownerUid: "alice" } },
      ),
    );
    assert.equal(result.metadata.contentType, "image/jpeg");
  });

  it("denies cross-user and executable uploads", async () => {
    const storage = env.authenticatedContext("mallory").storage();
    await assertFails(
      uploadBytes(
        ref(storage, "users/alice/receipts/tx-1/receipt.jpg"),
        new Uint8Array([1]),
        { contentType: "image/jpeg", customMetadata: { ownerUid: "alice" } },
      ),
    );
    const alice = env.authenticatedContext("alice").storage();
    await assertFails(
      uploadBytes(
        ref(alice, "users/alice/receipts/tx-1/payload.bin"),
        new Uint8Array([1]),
        { contentType: "application/octet-stream", customMetadata: { ownerUid: "alice" } },
      ),
    );
  });
});
