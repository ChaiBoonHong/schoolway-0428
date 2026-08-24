# Firebase Backend Instructions

Agent-Contract-Version: 1

Read the repository root `AGENTS.md` first.

- Use Application Default Credentials; never load a repository service-account JSON file.
- Callable Functions must require authentication, resolve the caller's authoritative role server-side, validate inputs, and return stable error codes.
- Keep privileged Auth lifecycle and notification fan-out on the backend.
- Use Firebase Auth UID for ownership and authorization fields.
- Prefer idempotent writes and explicitly handle retries from event triggers.
- Add Node tests for policy changes and Emulator tests for Firestore boundary changes.
- Do not log tokens, credentials, full private profiles, or child data.

