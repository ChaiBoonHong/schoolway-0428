# Firebase reset

`reset_firebase_project.js` deletes every document in the SchoolWay Firestore
database and every Firebase Authentication account for one named project. It is
not part of the app or deployment process.

Use it only after confirming the Firebase project ID, taking any required
backup, and obtaining explicit approval for that environment. It refuses to
run until the project ID is supplied twice:

```powershell
cd functions
$env:SCHOOLWAY_RESET_ADMIN_PASSWORD = 'A-temporary-password'
node scripts/reset_firebase_project.js --project PROJECT_ID --apply --confirm-delete-project PROJECT_ID --admin-email admin@schoolway.com
```

The command uses Application Default Credentials. Do not add service-account
keys to this repository.
