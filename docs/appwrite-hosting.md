## Host Flutter Web on Appwrite Sites

This project can be hosted as a static site on Appwrite by deploying `build/web`.

### 1) Install Appwrite CLI (Windows)

Use one of these:

- `npm install -g appwrite-cli`
- or `iwr -useb https://appwrite.io/cli/install.ps1 | iex`

Then confirm:

- `appwrite --version`

### 2) Build Flutter web

From the project root:

- `flutter build web --release`

This generates the deployable output in `build/web`.

### 3) Log in to Appwrite

- `appwrite login`

If your project is self-hosted, use:

- `appwrite client --endpoint "https://<your-appwrite-endpoint>/v1"`

### 4) Create an Appwrite site (one-time)

- `appwrite sites create --siteId "schoolway-web" --name "Schoolway Web"`

If your project uses teams, add `--teamId "<team-id>"`.

### 5) Deploy the built site

- `appwrite sites create-deployment --siteId "schoolway-web" --code "./build/web" --activate true`

### 6) Set framework settings in Appwrite Console

In **Console -> Sites -> schoolway-web -> Settings**:

- Framework: `Other` (or `Flutter` if shown)
- Build output directory: `build/web`
- SPA fallback: rewrite unknown routes to `/index.html` (recommended for Flutter web routing)

### 7) Update the site

Whenever you change the app:

1. `flutter build web --release`
2. `appwrite sites create-deployment --siteId "schoolway-web" --code "./build/web" --activate true`

