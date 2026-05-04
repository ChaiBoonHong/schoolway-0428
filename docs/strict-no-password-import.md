# Strict no-password-needed import mode

This mode allows user CSV import to link an existing Firebase Auth account by email, without requiring that user's password in CSV.

## What it does

- If email does not exist in Firebase Auth: create auth user normally.
- If email already exists in Firebase Auth and no Firestore user doc exists:
  - Flutter app calls Cloud Function `getAuthUidByEmail`.
  - Cloud Function uses Firebase Admin SDK to resolve UID by email.
  - Importer creates Firestore `users/{username}` with that UID in `authUid`.

## Security model

- Only signed-in Admin users can call `getAuthUidByEmail`.
- Admin check is done by looking up caller `auth.uid` in Firestore `users` where:
  - `authUid == caller uid`
  - `role == "Admin"`

## One-time setup

1. Install functions dependencies:
   - `cd functions`
   - `npm install`
2. Deploy function:
   - `firebase deploy --only functions:getAuthUidByEmail`
3. Ensure importer is signed in as an Admin account.

## App behavior

- In CSV Management -> Import -> User, turn on:
  - `Strict no-password-needed mode`
- Password can be empty only for rows that match existing Firebase Auth emails.
- For brand-new emails, password is still required to create the auth account.
