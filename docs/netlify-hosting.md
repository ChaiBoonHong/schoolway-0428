## Host Flutter Web on Netlify

This project can be hosted on Netlify by deploying `build/web`.

### 1) Create `netlify.toml` (already added)

The project includes:

- Build command: `flutter build web --release`
- Publish directory: `build/web`
- SPA fallback rewrite: `/* -> /index.html`

### 2) Deploy from Netlify UI (quickest)

1. Push this repository to GitHub/GitLab/Bitbucket.
2. In Netlify, click **Add new site -> Import an existing project**.
3. Select this repository.
4. Build settings:
   - Build command: `flutter build web --release`
   - Publish directory: `build/web`
5. Deploy.

### 3) Ensure Flutter is available in Netlify build image

Netlify does not include Flutter by default. Add one of these:

- Option A: Use a plugin that installs Flutter in build.
- Option B: Deploy prebuilt static files (`build/web`) using drag-and-drop/manual deploy.

If you use manual deploy, run locally first:

- `flutter build web --release`

Then upload the generated `build/web` folder to Netlify.

### 4) SPA routing

For Flutter web routes to work on refresh and deep links, Netlify must rewrite unknown paths to `index.html`.

This is already configured in `netlify.toml` and also in `web/_redirects`.

### 5) Update the site

Whenever you change the app:

1. `flutter build web --release` (if manual deploy)
2. Redeploy from Netlify UI or push a new commit if using Git-based deploys.
