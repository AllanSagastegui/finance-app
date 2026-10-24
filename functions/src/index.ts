import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

initializeApp();
const db = getFirestore();

type Tx = {
  type: "expense" | "income" | "transfer" | "adjustment";
  amountMinor: number;
  status: "posted" | "pending" | "void";
  currencyCode: string;
  occurredAt: FirebaseFirestore.Timestamp;
  categoryId?: string;
  accountId?: string;
  destinationAccountId?: string;
  goalId?: string;
};

function signedAmount(tx?: Tx): number {
  if (!tx || tx.status !== "posted" || tx.type === "transfer") return 0;
  return tx.type === "expense" ? -tx.amountMinor : tx.amountMinor;
}

type SummaryDelta = {
  incomeMinor: number;
  expenseMinor: number;
  netMinor: number;
  currencyCode: string;
};

function addSummaryDelta(
  deltas: Map<string, SummaryDelta>,
  tx: Tx | undefined,
  multiplier: number,
): void {
  if (!tx || tx.status !== "posted" || tx.type === "transfer") return;
  const period = tx.occurredAt.toDate().toISOString().slice(0, 7);
  const current = deltas.get(period) ?? {
    incomeMinor: 0,
    expenseMinor: 0,
    netMinor: 0,
    currencyCode: tx.currencyCode,
  };
  if (tx.type === "expense") current.expenseMinor += multiplier * tx.amountMinor;
  if (tx.type === "income") current.incomeMinor += multiplier * tx.amountMinor;
  current.netMinor += multiplier * signedAmount(tx);
  deltas.set(period, current);
}

function addAccountDelta(
  deltas: Map<string, number>,
  tx: Tx | undefined,
  multiplier: number,
): void {
  if (!tx || tx.status !== "posted") return;
  const add = (id: string | undefined, value: number) => {
    if (id) deltas.set(id, (deltas.get(id) ?? 0) + value);
  };
  if (tx.type === "transfer") {
    add(tx.accountId, -multiplier * tx.amountMinor);
    add(tx.destinationAccountId, multiplier * tx.amountMinor);
  } else {
    add(tx.accountId, multiplier * signedAmount(tx));
  }
}

export const onTransactionWrite = onDocumentWritten(
  { document: "users/{uid}/transactions/{transactionId}", region: "us-central1" },
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() as Tx : undefined;
    const after = event.data?.after.exists ? event.data.after.data() as Tx : undefined;
    if (!after && !before) return;

    const summaryDeltas = new Map<string, SummaryDelta>();
    addSummaryDelta(summaryDeltas, before, -1);
    addSummaryDelta(summaryDeltas, after, 1);
    const accountDeltas = new Map<string, number>();
    addAccountDelta(accountDeltas, before, -1);
    addAccountDelta(accountDeltas, after, 1);
    const budgetDeltas = new Map<string, number>();
    const goalDeltas = new Map<string, number>();
    const addPlanDelta = (tx: Tx | undefined, multiplier: number) => {
      if (!tx || tx.status !== "posted") return;
      if (tx.type === "expense" && tx.categoryId) {
        budgetDeltas.set(
          tx.categoryId,
          (budgetDeltas.get(tx.categoryId) ?? 0) + multiplier * tx.amountMinor,
        );
      }
      if (tx.type === "transfer" && tx.goalId) {
        goalDeltas.set(
          tx.goalId,
          (goalDeltas.get(tx.goalId) ?? 0) + multiplier * tx.amountMinor,
        );
      }
    };
    addPlanDelta(before, -1);
    addPlanDelta(after, 1);

    const marker = db.doc(`functionEvents/${event.id}`);
    await db.runTransaction(async (transaction) => {
      if ((await transaction.get(marker)).exists) return;
      const budgets = await transaction.get(
        db.collection(`users/${event.params.uid}/budgets`).where("active", "==", true),
      );
      for (const [period, delta] of summaryDeltas) {
        const summary = db.doc(
          `users/${event.params.uid}/monthlySummaries/${period}`,
        );
        transaction.set(summary, {
          currencyCode: delta.currencyCode,
          netMinor: FieldValue.increment(delta.netMinor),
          expenseMinor: FieldValue.increment(delta.expenseMinor),
          incomeMinor: FieldValue.increment(delta.incomeMinor),
          updatedAt: FieldValue.serverTimestamp(),
          schemaVersion: 1,
        }, { merge: true });
      }
      for (const [accountId, delta] of accountDeltas) {
        transaction.update(
          db.doc(`users/${event.params.uid}/accounts/${accountId}`),
          {
            currentBalanceMinor: FieldValue.increment(delta),
            updatedAt: FieldValue.serverTimestamp(),
          },
        );
      }
      for (const budget of budgets.docs) {
        const data = budget.data();
        const delta = data.categoryId === "all" || data.categoryId === "other"
          ? [...budgetDeltas.values()].reduce((sum, value) => sum + value, 0)
          : budgetDeltas.get(data.categoryId) ?? 0;
        if (delta !== 0) {
          transaction.update(budget.ref, {
            spentMinor: FieldValue.increment(delta),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
      for (const [goalId, delta] of goalDeltas) {
        transaction.update(
          db.doc(`users/${event.params.uid}/goals/${goalId}`),
          {
            savedAmountMinor: FieldValue.increment(delta),
            updatedAt: FieldValue.serverTimestamp(),
          },
        );
      }
      transaction.create(marker, {
        functionName: "onTransactionWrite",
        processedAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      });
    });
    logger.info("transaction_aggregated", { eventId: event.id });
  },
);

export const materializeRecurring = onSchedule(
  { schedule: "every day 02:15", timeZone: "UTC", region: "us-central1", maxInstances: 1 },
  async () => {
    const due = await db.collectionGroup("recurringRules")
      .where("active", "==", true)
      .where("nextRunAt", "<=", new Date())
      .limit(500)
      .get();
    for (const rule of due.docs) {
      const uid = rule.ref.parent.parent?.id;
      if (!uid) continue;
      await db.runTransaction(async (transaction) => {
        const fresh = await transaction.get(rule.ref);
        const data = fresh.data();
        if (!data?.active || !data.nextRunAt || data.nextRunAt.toMillis() > Date.now()) return;
        const dueAt = data.nextRunAt.toDate() as Date;
        const period = dueAt.toISOString().slice(0, 10);
        const id = `${rule.id}_${period}`;
        const movement = db.doc(`users/${uid}/transactions/${id}`);
        transaction.create(movement, {
          type: data.type,
          amountMinor: data.amountMinor,
          currencyCode: data.currencyCode,
          accountId: data.accountId,
          categoryId: data.categoryId ?? null,
          description: data.description ?? "",
          occurredAt: data.nextRunAt,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          recurringRuleId: rule.id,
          status: "posted",
          schemaVersion: 1,
        });
        const next = new Date(dueAt);
        if (data.frequency === "weekly") next.setUTCDate(next.getUTCDate() + 7);
        else if (data.frequency === "yearly") next.setUTCFullYear(next.getUTCFullYear() + 1);
        else next.setUTCMonth(next.getUTCMonth() + 1);
        transaction.update(rule.ref, {
          nextRunAt: next,
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    }
  },
);

export const createExport = onCall(
  { region: "us-central1", enforceAppCheck: true, maxInstances: 10, timeoutSeconds: 120 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required");
    const format = request.data?.format === "json" ? "json" : "csv";
    const exportRef = db.collection(`users/${uid}/exports`).doc();
    await exportRef.set({ status: "processing", format, createdAt: FieldValue.serverTimestamp() });

    const snapshot = await db.collection(`users/${uid}/transactions`)
      .orderBy("occurredAt", "desc").limit(5000).get();
    const rows = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    const body = format === "json"
      ? JSON.stringify(rows)
      : ["id,type,amountMinor,currencyCode,occurredAt,description",
        ...rows.map((row: Record<string, unknown>) => [
          row.id, row.type, row.amountMinor, row.currencyCode,
          (row.occurredAt as FirebaseFirestore.Timestamp)?.toDate().toISOString(),
          `"${String(row.description ?? "").replaceAll('"', '""')}"`,
        ].join(","))].join("\n");
    const path = `users/${uid}/exports/${exportRef.id}.${format}`;
    await getStorage().bucket().file(path).save(body, {
      contentType: format === "json" ? "application/json" : "text/csv",
      metadata: { cacheControl: "private, max-age=0" },
    });
    await exportRef.update({ status: "ready", storagePath: path, completedAt: FieldValue.serverTimestamp() });
    return { exportId: exportRef.id };
  },
);

export const deleteAccountData = onCall(
  { region: "us-central1", enforceAppCheck: true, maxInstances: 5, timeoutSeconds: 540 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required");
    const userRef = db.doc(`users/${uid}`);
    await db.recursiveDelete(userRef);
    await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
    await getAuth().deleteUser(uid);
    logger.info("account_deleted", { correlationId: request.rawRequest.get("x-cloud-trace-context") });
    return { status: "deleted" };
  },
);

export const cleanupExpiredExports = onSchedule(
  { schedule: "every day 04:30", timeZone: "UTC", region: "us-central1", maxInstances: 1 },
  async () => {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const old = await db.collectionGroup("exports").where("createdAt", "<", cutoff).limit(500).get();
    for (const doc of old.docs) {
      const data = doc.data();
      if (typeof data.storagePath === "string") {
        await getStorage().bucket().file(data.storagePath).delete({ ignoreNotFound: true });
      }
      await doc.ref.delete();
    }
  },
);
