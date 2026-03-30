---
name: senyamatika-techstack
description: >-
  Describes the Senya/Senyamatika monorepo tech stack across backend (Node/Express),
  Senyamatika (Flutter), and website (Vite/React). Use when implementing features,
  debugging, onboarding, or choosing libraries in this repository. Prefer official
  documentation and framework best practices; do not treat existing code as the
  source of truth for architecture or style when it conflicts with those docs.
---

# Senyamatika repository tech stack

## Repository layout

| Area | Path | Role |
|------|------|------|
| API & server logic | `backend/` | REST API, auth, AI, SQLite persistence |
| Mobile/desktop app | `Senyamatika/` | Flutter learning app |
| Web portal | `website/` | Teacher/admin style SPA (Vite + React) |

---

## Backend (`backend/`)

**Runtime & language:** Node.js with **TypeScript** (ES modules: `"type": "module"`), compiled with `tsc`; dev uses `tsx`.

**HTTP:** **Express** 4.x. Follow [Express routing](https://expressjs.com/en/guide/routing.html), [middleware](https://expressjs.com/en/guide/using-middleware.html), and security guidance (helmet-style headers, sane CORS, body size limits where applicable).

**Validation:** Prefer **Zod** for request/body parsing and domain validation; **express-validator** may appear for route-level checks—use one consistent approach per route layer and validate all untrusted input.

**Database:** **sql.js** (SQLite in WebAssembly / in-process file). Treat the DB file as a deployment artifact; use parameterized queries, migrations or versioned schema (`schema-sqlite.sql`), and avoid string-concatenated SQL.

**Auth & crypto:** **jsonwebtoken** (JWT), **bcrypt** for password hashing. Store secrets in environment variables only; never commit keys. Follow [JWT best practices](https://datatracker.ietf.org/doc/html/rfc8725) (short-lived tokens, secure algorithms, careful storage on clients).

**AI:** **@google/generative-ai** for Gemini. Consult [Google AI Gemini API docs](https://ai.google.dev/gemini-api/docs) for models, quotas, and SDK usage; keep API keys server-side.

**Other notable libs:** **cors**, **dotenv** / `node --env-file`, **pdfkit**, **csv-writer**.

**Best-practice anchors**

- [Node.js best practices](https://github.com/goldbergyoni/nodebestpractices) (high-level checklist).
- [TypeScript handbook](https://www.typescriptlang.org/docs/handbook/intro.html)—backend uses `strict: true`; preserve that.
- [Zod](https://zod.dev/) for schema-first validation.

---

## Senyamatika app (`Senyamatika/`)

**Framework:** **Flutter** (Dart SDK `>=3.0.0 <4.0.0`). Follow [Flutter documentation](https://docs.flutter.dev/) and [Effective Dart](https://dart.dev/effective-dart).

**State management:** **provider**—use `ChangeNotifier` / `Consumer` patterns per [provider package](https://pub.dev/packages/provider) and Flutter’s [state management overview](https://docs.flutter.dev/data-and-backend/state-mgmt/options).

**Local persistence:** **hive** + **hive_flutter** with **path_provider**; code generation via **hive_generator** and **build_runner** where types are used. See [Hive documentation](https://docs.hivedb.dev/).

**Networking & platform:** **http**, **url_launcher**, **shared_preferences**, **permission_handler**, **google_sign_in**, **speech_to_text**, **webview_flutter**, **video_player**, **google_fonts**.

**Quality:** **flutter_lints** in `analysis_options.yaml` (if present)—respect lints; prefer composition over huge monolithic widgets.

**Best-practice anchors**

- [Flutter app architecture](https://docs.flutter.dev/app-architecture) (layering, testability).
- [Material design in Flutter](https://docs.flutter.dev/ui/design/material) (`uses-material-design: true`).

---

## Website (`website/`)

**Build tool:** **Vite** 6.x with **@vitejs/plugin-react**. **Not Next.js**—routing is client-side.

**UI:** **React** 18 with **TypeScript**. **React Router** 7 (`react-router`, `react-router-dom`) for SPA navigation—follow [React Router docs](https://reactrouter.com/).

**Styling:** **Tailwind CSS** 4 with **@tailwindcss/vite**; **tailwind-merge**, **clsx**, **class-variance-authority** for component variants.

**Component libraries:** Large **Radix UI** primitives set; **MUI** (`@mui/material`, **@emotion**); **lucide-react** icons. Prefer one primary system per feature area to avoid inconsistent patterns; compose accessible primitives (Radix) with project design tokens.

**Forms & UX:** **react-hook-form**, **sonner** (toasts), **vaul**, **cmdk**, **motion**, **recharts**, **react-dnd**, **jspdf** / **jspdf-autotable**.

**3D / visuals:** **three**, **@react-three/fiber**, **@react-three/drei**, **@react-spring/three**, **@shadergradient/react**—follow [React Three Fiber docs](https://docs.pmnd.rs/react-three-fiber) and Three.js guides when touching 3D.

**Path alias:** `@/` → `src/` (see `vite.config.ts`).

**Best-practice anchors**

- [Vite guide](https://vite.dev/guide/), [React](https://react.dev/).
- [Tailwind CSS v4](https://tailwindcss.com/docs).
- [Radix primitives](https://www.radix-ui.com/primitives), [MUI](https://mui.com/material-ui/getting-started/).

---

## Cross-cutting guidance for agents

1. **Official docs over local habits:** When suggesting refactors or new code, align with the documentation links above. Existing files may mix patterns (e.g. multiple UI libraries); prefer consistency and accessibility, not “copy the largest file.”
2. **Security:** Validate input on the server; keep Gemini and JWT secrets on the backend; use HTTPS in production; follow OWASP summaries for web and API exposure.
3. **Secrets:** `.env` / `.env.local` patterns belong in gitignore; never embed keys in Flutter, Vite, or committed JSON.
4. **Dependencies:** Add packages only when necessary; match the major versions already declared in `package.json` / `pubspec.yaml` unless upgrading is explicitly requested.

## Optional deeper reference

For long checklists or version-specific notes, add a sibling `reference.md` in this folder and link it here—keep this file concise.
