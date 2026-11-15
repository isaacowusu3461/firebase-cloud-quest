
const fs = require("node:fs");
const path = require("node:path");
const { before, after, beforeEach, test } = require("node:test");
const assert = require("node:assert/strict");

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;

const projectId = "fir-cloud-quest";

// I use two different students to check that progress is private.
const studentA = "student-a";
const studentB = "student-b";

before(async () => {
  const rulesPath = path.resolve(__dirname, "../../firestore.rules");

  // Load the same rules used by the Firestore emulator.
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(rulesPath, "utf8"),
    },
  });
});

beforeEach(async () => {
  // Start each test with clean Firestore data.
  await testEnv.clearFirestore();

  // Admin-style setup bypasses the rules so I can prepare test data.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await db.doc("challenges/today").set({
      title: "First Cloud Quest",
      prompt: "Explain why Firebase Authentication is important.",
    });

    await db.doc(`users/${studentA}/progress/today`).set({
      completed: true,
      points: 10,
      badgeId: "first-quest",
    });

    await db.doc(`users/${studentB}/progress/today`).set({
      completed: false,
      points: 0,
      badgeId: "",
    });
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

test("Signed-in student can read the daily challenge", async () => {
  const db = testEnv.authenticatedContext(studentA).firestore();

  await assertSucceeds(db.doc("challenges/today").get());
});

test("Signed-out user cannot read the daily challenge", async () => {
  const db = testEnv.unauthenticatedContext().firestore();

  await assertFails(db.doc("challenges/today").get());
});

test("Student can read their own progress", async () => {
  const db = testEnv.authenticatedContext(studentA).firestore();

  await assertSucceeds(
    db.doc(`users/${studentA}/progress/today`).get()
  );
});

test("Student cannot change their own points", async () => {
  const db = testEnv.authenticatedContext(studentA).firestore();

  // A student tries to give themselves 100 points.
  await assertFails(
    db.doc(`users/${studentA}/progress/today`).update({
      points: 100,
    })
  );
});

test("Student cannot read another student's progress", async () => {
  const db = testEnv.authenticatedContext(studentA).firestore();

  await assertFails(
    db.doc(`users/${studentB}/progress/today`).get()
  );
});

test("Student cannot change another student's progress", async () => {
  const db = testEnv.authenticatedContext(studentA).firestore();

  await assertFails(
    db.doc(`users/${studentB}/progress/today`).update({
      points: 100,
    })
  );
});

test("Student cannot edit the daily challenge", async () => {
  const db = testEnv.authenticatedContext(studentA).firestore();

  await assertFails(
    db.doc("challenges/today").update({
      title: "Changed Challenge",
    })
  );
});

