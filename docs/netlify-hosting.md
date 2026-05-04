## Host Flutter Web on Netlify

This project can be hosted on Netlify by deploying `build/web`.

### 1) Create `netlify.toml` (already added)

The project includes:

- Build command: `flutter build web --release`
- Publish directory: `build/web`
- SPA fallback rewrite: `/* -> /index.html`

### 2) Push latest commit first

Make sure your latest commit (with `netlify.toml`) is pushed to the branch Netlify deploys.

### 3) Deploy from Netlify UI (quickest)

1. Push this repository to GitHub/GitLab/Bitbucket.
2. In Netlify, click **Add new site -> Import an existing project**.
3. Select this repository.
4. Build settings:
   - Base directory: leave empty
   - Build command: leave empty to use `netlify.toml` (recommended)
   - Publish directory: leave empty to use `netlify.toml` (recommended)
5. Deploy.

### 4) Ensure Flutter is available in Netlify build image

This repo's `netlify.toml` installs Flutter automatically and builds web output.

If you prefer manual deploy instead:

1. Run `flutter build web --release` locally.
2. Upload `build/web` in Netlify manual deploy.

### 5) SPA routing

For Flutter web routes to work on refresh and deep links, Netlify must rewrite unknown paths to `index.html`.

This is already configured in `netlify.toml` and also in `web/_redirects`.

### 6) Update the site

Whenever you change the app:

1. `flutter build web --release` (if manual deploy)
2. Redeploy from Netlify UI or push a new commit if using Git-based deploys.
