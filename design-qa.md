# Driver map and student attendance design QA

**Source visual truth**

- Map source: `C:\Users\ADMINI~1\AppData\Local\Temp\codex-clipboard-80e7e5ff-9fa8-412f-bd6e-a630aa49058a.png` (627 x 332).
- Roster source: `C:\Users\ADMINI~1\AppData\Local\Temp\codex-clipboard-838f5323-2938-4758-8ba1-5363b2365d7c.png` (598 x 313).
- Intended state: active driver session, simulation available, one expanded stop, and a waiting student with manual attendance.

**Implementation evidence**

- Local Flutter web build: `http://127.0.0.1:4173`.
- Release web and Android builds completed successfully.
- Browser-rendered implementation screenshot: unavailable. The in-app Browser control surface was not callable in this task, and the active driver state requires authentication and Firebase data.
- Viewport and density: not measurable without the browser-rendered capture.

**Required fidelity surfaces**

- Fonts and typography: Lexend and the existing SchoolWay text theme are preserved in code; rendered fidelity could not be compared.
- Spacing and layout rhythm: the simulator is now a 48 x 48 control below Zoom Out, and roster groups use the shared 20 px large-radius token; rendered spacing could not be compared.
- Colors and visual tokens: blue-tinted surfaces use `ColorScheme.primaryContainer`; light and dark palettes are defined by `SchoolWayTheme`.
- Image quality and asset fidelity: no new raster or custom image assets were introduced; standard Material icons are used.
- Copy and content: the roster heading is removed and new attendance, status, queue, and action copy is localized.

**Findings**

- [P2] Runtime visual comparison is unavailable.
  Location: Driver Map and Driver Students tabs.
  Evidence: both source screenshots were opened, but no authenticated implementation screenshot could be captured through the supported in-app Browser surface.
  Impact: exact visual spacing, text wrapping, dark-mode appearance, and 200% text-scale rendering remain unverified visually.
  Fix: open the local app in an authenticated driver session, capture phone and tablet views in light and dark mode, and compare them side by side with the source screenshots.

**Implementation checklist**

- [x] Move the icon-only simulator below Zoom Out.
- [x] Remove the Student Roster heading.
- [x] Apply rounded blue stop and student cards.
- [x] Add pending-sync and truthful Firebase result states.
- [x] Run static analysis, Flutter tests, Firestore Emulator tests, and release builds.
- [ ] Capture authenticated phone/tablet implementation screenshots and complete the visual comparison.

final result: blocked
