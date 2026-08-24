const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

const projectId = argument("--project");
const databaseId = argument("--database");
const confirmation = argument("--confirm");
const expectedConfirmation = `ERASE-${projectId}-${databaseId}`;

if (!projectId || !databaseId || confirmation !== expectedConfirmation) {
  console.error(
    "Refusing to erase data. Supply --project, --database, and " +
      `--confirm ${expectedConfirmation}`,
  );
  process.exit(2);
}

const firebaseApp = initializeApp({ projectId });
const auth = getAuth(firebaseApp);
const db = getFirestore(firebaseApp, databaseId);

const nestedCollectionIds = ["devices", "breadcrumbs", "members"];

async function deleteSnapshot(snapshot) {
  let deleted = 0;
  for (let offset = 0; offset < snapshot.docs.length; offset += 400) {
    const batch = db.batch();
    const chunk = snapshot.docs.slice(offset, offset + 400);
    for (const document of chunk) batch.delete(document.ref);
    await batch.commit();
    deleted += chunk.length;
  }
  return deleted;
}

async function eraseFirestore() {
  let deletedCount = 0;

  // Delete known nested records first so their missing parent documents do not
  // leave data hidden from ordinary top-level collection queries.
  for (const collectionId of nestedCollectionIds) {
    const snapshot = await db.collectionGroup(collectionId).get();
    deletedCount += await deleteSnapshot(snapshot);
    console.log(
      `Erased ${snapshot.size} nested document(s) from ${collectionId}.`,
    );
  }

  while (true) {
    const collections = await db.listCollections();
    let passCount = 0;
    for (const collection of collections) {
      const snapshot = await collection.limit(400).get();
      passCount += await deleteSnapshot(snapshot);
    }
    deletedCount += passCount;
    if (passCount === 0) break;
  }

  const collections = await db.listCollections();
  let remainingCount = 0;
  for (const collection of collections) {
    remainingCount += (await collection.get()).size;
  }
  if (remainingCount !== 0) {
    throw new Error(`${remainingCount} top-level Firestore document(s) remain.`);
  }

  console.log(
    `Erased ${deletedCount} Firestore document(s) from database ` +
      `${databaseId} in ${projectId}.`,
  );
}

async function eraseAuth() {
  let nextPageToken;
  let deletedCount = 0;
  do {
    const result = await auth.listUsers(1000, nextPageToken);
    const uids = result.users.map((user) => user.uid);
    if (uids.length > 0) {
      const deletion = await auth.deleteUsers(uids);
      deletedCount += deletion.successCount;
      if (deletion.failureCount > 0) {
        throw new Error(`Failed to delete ${deletion.failureCount} Auth users.`);
      }
    }
    nextPageToken = result.pageToken;
  } while (nextPageToken);
  console.log(`Deleted ${deletedCount} Firebase Auth users.`);
}

async function main() {
  console.log(`Target project: ${projectId}`);
  console.log(`Target database: ${databaseId}`);
  await eraseFirestore();
  await eraseAuth();
}

main().catch((error) => {
  console.error("Database erasure failed:", error.message);
  process.exit(1);
});
