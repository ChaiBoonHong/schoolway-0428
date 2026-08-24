# SchoolWay Agent Contract

Agent-Contract-Version: 1

This file is the canonical instruction source for every AI agent working in this repository. Tool-specific instruction files are adapters only. Read this file and the nearest scoped `AGENTS.md` before changing code.

## Product priorities

1. Protect children, families, drivers, and school data through least-privilege access.
2. Keep the SchoolWay UI consistent across Parent, Driver, and Admin experiences.
3. Preserve the blue/cyan identity, Lexend typography, and established information architecture.
4. Prefer reliable, testable behavior over visual or architectural novelty.

## Required workflow

1. Inspect the relevant implementation, callers, data model, and nearest tests.
2. State assumptions that materially affect behavior.
3. Preserve unrelated user changes and existing working behavior.
4. Implement through existing shared boundaries instead of duplicating logic.
5. Add or update tests for changed behavior and failure paths.
6. Run the narrowest checks first, then the owning package checks.
7. Report the outcome, files changed, commands run, failures, limitations, and owner-only actions.

Never claim that a test, build, deployment, screenshot, or accessibility check ran unless it actually ran.

## UI non-negotiables

- Use `SchoolWayTheme`, semantic theme extensions, and shared components. Do not introduce ordinary hardcoded colors, radii, spacing, typography, or repeated button styles.
- Preserve responsive behavior at phone (<600), tablet (600-1023), and desktop (>=1024) widths.
- Support light, dark, and system themes.
- Put every new user-facing string in Flutter localization resources.
- Respect system text scaling and reduced-motion preferences.
- Add semantic labels, keyboard behavior, visible focus, and meaningful error recovery.
- Keep interactive targets at least 48x48 logical pixels.
- Never communicate emergency or status meaning by color alone.
- For visible UI work, capture and inspect before/after states at the affected breakpoints and theme modes when a supported capture surface is available.

## Security non-negotiables

- Never commit credentials, private keys, tokens, customer data, or exported production data.
- Firebase Auth UID is the authorization identity. Usernames are display/login metadata only.
- Never broaden a Firestore rule to work around a permission error.
- Validate authorization in callable Functions even when the client hides the action.
- Add Firebase Emulator tests for every Firestore rule change.
- Users must never be able to change their own role, UID, active status, or another user's profile.
- Drivers may operate only their assigned bus/session. Parents may access only linked children and transport records.
- Server code owns account provisioning and operational notification fan-out.

## Safety boundaries

Agents may inspect, edit, and test locally when requested. Do not deploy, rotate credentials, rewrite shared Git history, force-push, delete cloud data, submit external forms, or perform another destructive/external action without explicit approval for that exact action.

## Definition of done

- `dart format --output=none --set-exit-if-changed lib test tool` passes.
- `flutter analyze` and `flutter test` pass.
- Functions tests and production dependency audit pass without critical/high findings.
- Firebase Emulator rule tests pass when security rules change.
- `dart run tool/verify_project_standards.dart` passes.
- Relevant release builds succeed.
- The final diff contains no unrelated changes or secret material.

