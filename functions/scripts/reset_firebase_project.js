/*
 * Destructive SchoolWay Firebase reset utility.
 *
 * This file intentionally performs a dry run unless all three explicit
 * confirmations are supplied. It deletes every Firestore document (including
 * subcollections) in the configured SchoolWay database and every Firebase
 * Authentication account in the named project.
 *
 * Usage, from functions/:
 *   node scripts/reset_firebase_project.js --project PROJECT_ID
 *   node scripts/reset_firebase_project.js --project PROJECT_ID --apply \
 *     --confirm-delete-project PROJECT_ID
 */
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function allAuthUids(auth) {
  const uids = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    uids.push(...page.users.map((user) => user.uid));
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

async function deleteCollectionDocuments(database, collection) {
  const documents = await collection.get();
  for (const document of documents.docs) {
    await database.recursiveDelete(document.ref);
  }
}

async function main() {
  const projectId = argument("--project");
  const confirmation = argument("--confirm-delete-project");
  const adminEmail = argument("--admin-email")?.trim().toLowerCase();
  const adminPassword = process.env.SCHOOLWAY_RESET_ADMIN_PASSWORD;
  const apply = process.argv.includes("--apply");
  if (!projectId || !/^[a-z][a-z0-9-]{4,62}$/.test(projectId)) {
    throw new Error("Pass a valid Firebase project ID with --project PROJECT_ID.");
  }
  if (!apply || confirmation !== projectId) {
    throw new Error(
      "Dry run only. Re-run with --apply --confirm-delete-project PROJECT_ID to delete data.",
    );
  }
  if ((adminEmail && !adminPassword) || (!adminEmail && adminPassword)) {
    throw new Error(
      "To recreate an admin, pass --admin-email and set SCHOOLWAY_RESET_ADMIN_PASSWORD.",
    );
  }
  if (adminPassword && adminPassword.length < 8) {
    throw new Error("SCHOOLWAY_RESET_ADMIN_PASSWORD must contain at least 8 characters.");
  }

  const app = initializeApp({ projectId });
  const database = getFirestore(app, "schoolway");
  const auth = getAuth(app);
  const [collections, uids] = await Promise.all([
    database.listCollections(),
    allAuthUids(auth),
  ]);

  console.log(`Deleting ${collections.length} Firestore root collection(s) and ${uids.length} Auth account(s) from ${projectId}.`);
  for (const collection of collections) {
    // recursiveDelete requires a document reference as its root. Deleting a
    // collection reference can complete without removing child documents.
    await deleteCollectionDocuments(database, collection);
  }
  for (let index = 0; index < uids.length; index += 1000) {
    await auth.deleteUsers(uids.slice(index, index + 1000));
  }
  if (adminEmail) {
    const admin = await auth.createUser({
      email: adminEmail,
      password: adminPassword,
      displayName: "SchoolWay Admin",
      disabled: false,
    });
    await database.collection("users").doc(admin.uid).set({
      authUid: admin.uid,
      username: "admin",
      email: adminEmail,
      role: "admin",
      isActive: true,
      firstName: "SchoolWay",
      lastName: "Admin",
      phoneNumber: "",
      countryCode: "+60",
      gender: null,
      birthday: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    // Delete access records generated for the erased fleet. The new admin has
    // administrative rule access and does not need a bus_access membership.
    await deleteCollectionDocuments(database, database.collection("bus_access"));
    console.log(`Recreated active admin account ${adminEmail}.`);
  }
  console.log(`Reset completed for ${projectId}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
