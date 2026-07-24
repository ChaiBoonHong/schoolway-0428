const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize the app.
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'schoolway-04286806'
});

async function eraseFirestore() {
  try {
    const db = admin.firestore();
    db.settings({ databaseId: 'schoolway' });
    const collections = await db.listCollections();
    if (collections.length === 0) {
      console.log('✅ Firestore is already empty.');
      return;
    }
    for (const collection of collections) {
      console.log(`Erasing Firestore collection: ${collection.id}...`);
      const snapshot = await collection.get();
      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });
      await batch.commit();
      console.log(`✅ Deleted ${snapshot.size} documents from ${collection.id}.`);
    }
    console.log('✅ Erased all Firestore collections in database "schoolway".');
  } catch (error) {
    console.error('❌ Error erasing Firestore:', error);
    process.exit(1);
  }
}

async function eraseAuth() {
  try {
    let nextPageToken;
    let deletedCount = 0;
    do {
      const listUsersResult = await admin.auth().listUsers(1000, nextPageToken);
      const uids = listUsersResult.users.map((userRecord) => userRecord.uid);
      
      if (uids.length > 0) {
        const deleteResult = await admin.auth().deleteUsers(uids);
        deletedCount += deleteResult.successCount;
      }
      nextPageToken = listUsersResult.pageToken;
    } while (nextPageToken);

    console.log(`✅ Deleted ${deletedCount} users from Auth.`);
  } catch (error) {
    console.error('❌ Error erasing Auth users:', error);
    process.exit(1);
  }
}

async function main() {
  await eraseFirestore();
  await eraseAuth();
  process.exit(0);
}

main();
