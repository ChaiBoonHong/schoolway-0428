# Flutter and UI Instructions

Agent-Contract-Version: 1

Read the repository root `AGENTS.md` first.

- Keep widgets presentation-focused; put persistence, authorization, and backend operations behind services/controllers/providers.
- Use Riverpod for application preferences and cross-screen application state. Dispose subscriptions and controllers deterministically.
- Use `SchoolWayTheme` and shared widgets. New feature files must not introduce raw `Color(0x...)` values or repeated component styling.
- Use the responsive role shell for role-level navigation. Test phone, tablet, and desktop layouts.
- Add strings to `lib/l10n/app_en.arb` and access them through generated localizations.
- Respect reduced motion through the shared motion preference, and preserve 200% text-scale reflow.
- Add semantics and keyboard support for custom controls.
- Never authorize an operation from a role value supplied by the client UI.

