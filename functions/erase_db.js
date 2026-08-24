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

async function eraseFirestore() {
  const collections = await db.listCollections();
  for (const collection of collections) {
    console.log(`Erasing Firestore collection: ${collection.id}`);
    await db.recursiveDelete(collection);
  }
  console.log(`Erased Firestore database ${databaseId} in ${projectId}.`);
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
