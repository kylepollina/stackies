# Stackies landing page

A one-page static site: `index.html` (inline CSS, Google Fonts only) plus `images/`. No build step. GitHub Pages
serves this folder from `main`.

**Preview locally:** open `docs/index.html` in a browser, or run `cd docs && python3 -m http.server 8000` and visit
http://localhost:8000.

**Screenshots** in `images/` come from the real app with made-up notes. Run a test copy with
`CFFIXED_USER_HOME` pointing at a folder with a seeded `Library/Application Support/Stackies/notes.json`, so your own
notes stay out of it. Crop any full-screen capture so that only the app and wallpaper show.
