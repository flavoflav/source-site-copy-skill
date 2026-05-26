---
name: site-copy
description: >-
  Copy a live website into Acquia Source (Canvas or Nebula) Workbench as components, styles, navigation, pages, AND Drupal content types with React components that render nodes via SWR. Full migration — visual clone to ≥99% parity, plus dynamic content (blog posts, articles, case studies, products) lifted into editor-managed content types with image fields, body HTML, and entity references, not hardcoded into static pages. Use whenever the user wants to copy, clone, recreate, or migrate any website into Source, Workbench, Canvas, Nebula, or Conductor — even without saying "skill" or "Source" explicitly. Triggers on "copy this site", "rebuild [URL] in Workbench", "recreate [URL] in Source", "clone [URL] for Canvas", "import all blog posts from [URL]", "migrate [URL]'s content into Drupal content types", "make a content type for X from [URL]", or any request to recreate a live site's design OR bring its repeatable content (blog, news, products, team) into Drupal as editor-managed content types.
---

# Site Copy to Source Workbench

Copy **$ARGUMENTS** into local Acquia Source Workbench. The bar is simple and non-negotiable: **screenshots of Workbench match screenshots of the live site at ≥99% parity, page for page, zero validation errors, ready to push to Source without manual cleanup.** Fast, repeatable, bug-free. Nothing else counts.

This skill exists because past runs (a) plateaued around 65–88% fidelity, (b) destroyed local work with bad sync commands, and (c) produced pages Source couldn't accept. The fixes are encoded here. Follow the steps in order. Do not skip the diff loop. Do not self-grade generously. Do not run destructive sync commands on uncommitted work.

---

## Pick a branch first: Canvas or Nebula

Before anything else, determine which Source build target this project uses. Check the project root for clues:

- `nebula.config.*`, a `nebula/` directory, or `npm run nebula:*` scripts → **Nebula branch**
- `canvas.config.*`, a `components/` tree with `component.yml` files, or `npx canvas *` scripts → **Canvas branch**
- Both present, or unclear → **ask the user**. Do not guess.

The branch determines which authoring skills you load in Step 0 and which build/verify skills you use in Steps 5–7. The recon, decomposition, tokens, media, and navigation steps (1–4) are identical for both.

Also detect the **remote target**: if `CANVAS_SITE_URL` ends with `.cms.acquia.site` or the host otherwise reads as Acquia Source, treat this as an **Acquia Source** project. That changes the push contract (Step 8). Note this *now* — getting it wrong later destroys local work.

---

## Step 0 — Load the right skills before writing any code

Read the `SKILL.md` of each listed skill in full before Step 1. If any are missing, stop and tell the user which one.

### Mandatory load — never skip (both branches)

These two skills are **load-bearing infrastructure** for every site-copy run. Do not advance past Step 0 if either is missing.

1. **`agent-browser`** — the only sanctioned way to drive Chrome/Safari for live-site capture, screenshotting, visual diffing, and DOM extraction (Steps 1, 1a, 1b, 7). Site-copy depends on its `--session`, `screenshot --full`, `eval --stdin`, and DOM-walk capabilities. Do **not** substitute generic browser tools, raw Playwright, or Claude-in-Chrome — agent-browser already encodes the capture patterns site-copy expects (combined `eval` per page, parallel `--session` browsers, the Workbench iframe screenshot trick).
2. **`local-power-tools`** — the project's local utility toolbox (file operations, parallel batch helpers, repo-aware scripts). Required for the per-batch git commits in Step 0.5, the media download/validate pipeline in Step 4, the page generator in Step 6, and the content-type import scripts in Step 4c. Site-copy authors scripts that lean on local-power-tools conventions; running without it produces ad-hoc scripts that don't compose with the rest of the workflow.

**Verification before any other work:** state to the user, in the first turn after the skill triggers:

> "Loading agent-browser and local-power-tools (both mandatory for site-copy). I'll abort if either is unavailable."

Then read each skill's `SKILL.md` in full. If a `Skill` tool call (or `Skill(skill_name=…)` invocation) errors, fails to surface, or the SKILL.md isn't readable — **stop**. Ask the user to install/enable the missing skill before continuing. Do not work around it. Site-copy's quality bar depends on the patterns these skills encode.

### Also load — workflow shaping (both branches)

3. `canvas-design-decomposition` — turning screenshots into a component catalog
4. `canvas-styling-conventions` — token vocabulary, what counts as a token vs. a hardcoded value
5. `frontend-design` — visual quality patterns
6. `implement-design` — generic implementation discipline (prop-driven, token-driven, no hardcoded copy)

### Canvas branch — also load

7. `canvas-component-definition` — `component.yml` structure, prop schemas
8. `canvas-component-metadata` — metadata fields, slots, examples
9. `canvas-component-composability` — when to use slots/children vs. props
10. `canvas-component-utils` — shared helpers and patterns
11. `canvas-page-definition` — page schema
12. `canvas-content-templates` — content type bindings (required for Step 4c: dynamic content as Drupal content types + auto-binding component props to entity fields)
13. `canvas-navigation-components` + `acquia-source-navigation-menus` — nav and menu wiring
14. `acquia-source-canvas-pages` — **how Canvas pages live in Source. Required reading on Acquia Source. Pages do NOT round-trip via canvas push/pull on Source.**
15. `canvas-data-fetching` — when components need real data
16. `canvas-workbench` — local Workbench operations
17. `canvas-component-push` — pushing finished components (components only — never `--include-pages` against Source)

### Nebula branch — also load

7. `nebula-project-structure`, 8. `nebula-scrape-url`, 9. `nebula-component-creation`,
10. `nebula-component-validation`, 11. `nebula-node-page-scaffold`, 12. `nebula-workbench-pages`,
13. `nebula-visual-verification` — Step 7 verification loop on Nebula.

---

## Step 0.5 — Pre-flight (do this before any authoring)

These checks prevent the most expensive failure modes from previous runs.

0. **Mandatory-skill gate.** Confirm that both `agent-browser` and `local-power-tools` skills have been loaded in this session (see Step 0). If either is missing — the `Skill` invocation failed, the SKILL.md couldn't be read, or you advanced without loading — **stop and abort the run**. Ask the user to install or enable the missing skill. Do not improvise with raw Playwright, generic browser tools, or hand-rolled scripts. The two skills encode site-copy's capture and local-utility patterns; running without them produces output that won't match the rest of the workflow.
1. **Git baseline.** Run `git status`. If the tree is dirty, stop and ask the user whether to commit or stash. Authoring on top of someone else's uncommitted work loses work when a later sync command runs.
2. **Commit checkpoints.** After each batch (components built, pages authored, tokens updated) run `git add -A && git commit -m "wip: site-copy <stage>"`. **No batch goes uncommitted before the next sync command.** This is the only recovery path from a destructive `canvas pull`. Treat git as the load-bearing safety net.
3. **Confirm the push contract.** State to the user, before authoring: "This is a {Canvas | Nebula} project targeting {Acquia Source | local-only | other}. I will push components only via `canvas push --yes` and **never** run `canvas push --include-pages`, `canvas reconcile-media`, or `canvas pull` against Acquia Source. Pages and media are authored via Source MCP."
4. **Source MCP connectivity gate (Acquia Source only).** Confirm that the Source MCP tools (`mcp__source-mcp__create_media`, `mcp__source-mcp__create_canvas_page`, `mcp__source-mcp__batch_add_components_to_page`, `mcp__source-mcp__publish_canvas_page`, `mcp__source-mcp__create_menu`, `mcp__source-mcp__create_menu_item`, `mcp__source-mcp__publish_auto_saves`, plus `mcp__source-mcp__create_content_type`, `mcp__source-mcp__batch_add_fields_to_content_type`, `mcp__source-mcp__batch_create_nodes` for Step 4c) are available **before any image scraping, page authoring, or content-type creation**.
   - If the tools appear in the available-skills / deferred-tools list → proceed.
   - If they are not connected → **stop, and ask the user to start the Source MCP server**. Do not proceed past Step 3 (Token extraction) without it. Suggested prompt: *"Source MCP appears disconnected. Please start the Source MCP server (or run the Source MCP plugin connection flow) and tell me when it's ready. I need `create_media`, `create_canvas_page`, `batch_add_components_to_page`, and `publish_canvas_page` to ship pages to Source — without them, the run cannot finish."*
   - **Verify the MCP is bound to the right Source.** Call `list_entities(entity_type="node", limit=1)` and check `canonicalUrl`. If the host doesn't match the Source URL the user is working with, the MCP is auth'd to a sibling install — re-auth via `mcp__source-mcp__authenticate` before any writes.
5. **Decide which page types become content types (Step 4c).** Walk the recon page list with the user. Repeatable list content (blog posts, news, products, case studies, team bios) → Drupal content types. One-of-a-kind marketing pages (home, pricing, about) → static `pages/*.json`. Capture the user's answer in `recon/content-types.json`. **Don't decide unilaterally** — editor workflow is the user's call, not yours.

---

## Step 1 — Capture (fast)

Get raw material in a single efficient pass. The old "open each page, networkidle, scroll, screenshot, then open again to extract DOM, then open again for media" pattern is wasteful. Do it in one pass per page.

### Canvas branch — combined per-page capture

For each page in the discovered list:

```bash
agent-browser --session sitecopy open <url>
agent-browser --session sitecopy wait --load networkidle
agent-browser --session sitecopy eval --stdin <<'EOF'
// One eval returns everything needed for Steps 1–4
(function(){
  // 1. Trigger lazy loads
  document.querySelectorAll('img[loading="lazy"]').forEach(i => i.loading = 'eager');
  // 2. Collect images (img elements + computed background-image)
  const imgs = Array.from(document.querySelectorAll('img'))
    .map(i => ({src: i.currentSrc || i.src, alt: i.alt || '', w: i.naturalWidth, h: i.naturalHeight}))
    .filter(x => x.src && !x.src.startsWith('data:'));
  // 3. Hero video poster fallback when there's no <img>
  const heroVideo = document.querySelector('section video, [class*="hero" i] video');
  const heroPoster = heroVideo?.poster || null;
  // 4. Computed styles for tokens
  const body = getComputedStyle(document.body);
  const h1 = document.querySelector('h1'); const h2 = document.querySelector('h2');
  const styles = {
    bodyFont: body.fontFamily, bodyColor: body.color,
    h1: h1 ? {size: getComputedStyle(h1).fontSize, weight: getComputedStyle(h1).fontWeight} : null,
    h2: h2 ? {size: getComputedStyle(h2).fontSize, weight: getComputedStyle(h2).fontWeight} : null
  };
  // 5. Headlines, body copy, CTAs for content
  const text = [];
  document.querySelectorAll('main h1, main h2, main h3, main p, main li, main button, main a')
    .forEach(el => { const t = (el.innerText || '').trim(); if (t && t.length < 800) text.push(`[${el.tagName}] ${t}`); });
  // 6. Navigation extraction (see Step 1a)
  const nav = window.__siteCopyExtractNav ? window.__siteCopyExtractNav() : null;
  return JSON.stringify({imgs, heroPoster, styles, text, nav});
})()
EOF
agent-browser --session sitecopy screenshot ./recon/screens/desktop/<slug>.png --full
```

Write the JSON output to `./recon/raw/<slug>.json`. The screenshot is captured in the same session without reloading the page.

### Nebula branch

Use `nebula-scrape-url` for the scrape — it handles DOM, assets, and computed styles in one pass. Fall back to `agent-browser` for anything `nebula-scrape-url` misses (notably nav interaction states — see Step 1a).

### Step 1a — Navigations (main + footer), captured separately and thoroughly

Navigation is special: it has interactive state (hover dropdowns, mega menus, mobile drawer) that a static DOM walk misses. Capture **both the main navigation AND the footer navigation** explicitly *before* the per-page loop runs. Both will become Drupal menus on Source (Step 4b) and live-CMS-linked components (Step 5). This is non-negotiable — 100% parity means menus are managed in the CMS, not hardcoded.

#### Main navigation

1. On the homepage, **before any hover**, take a screenshot of the header: `./recon/screens/desktop/_nav-default.png`.
2. Snapshot the DOM: list every nav root link (`header nav > a`, `header nav > button`, `header [role="menubar"] > *`).
3. For each nav root that opens a panel (look for `aria-haspopup`, `aria-expanded`, or a sibling `[role="menu"]`/`[class*="dropdown" i]`/`[class*="megamenu" i]` element):
   - Hover the root with `agent-browser hover @ref` (or `eval` with `dispatchEvent(new MouseEvent('mouseenter'))`). Many sites populate megamenu children only on hover — you **must** trigger each one and re-snapshot the DOM, otherwise children will be missing from `recon/nav.json` and the Source menu will be empty.
   - Wait 400ms for animations.
   - Screenshot: `./recon/screens/desktop/_nav-<rootLabel>.png`.
   - Snapshot the opened panel DOM: capture column headers, link groups, links, any promoted images.
4. Resize to 375px and screenshot the mobile nav closed + open (`./recon/screens/mobile/_nav-closed.png`, `_nav-open.png`). Trigger the hamburger and capture each expanded section.
5. Note sticky behavior: scroll 600px and screenshot to check whether the nav becomes solid/sticky.

Write to `./recon/nav.json`:

```json
{
  "logo": {"text": "Brand", "image": "https://..."},
  "sticky": true,
  "background": {"top": "transparent", "scrolled": "solid_white"},
  "menuMachineName": "main-nav",
  "items": [
    {"label": "Solutions", "href": null, "kind": "megamenu", "columns": [
      {"heading": "By industry", "links": [{"label": "Hospitality", "href": "/solutions/hospitality"}]},
      {"heading": "By size", "links": [...]}
    ]},
    {"label": "Pricing", "href": "/pricing", "kind": "link"},
    {"label": "Resources", "href": "/resources", "kind": "dropdown", "links": [...]}
  ],
  "cta": {"label": "Contact Sales", "href": "/contact-sales", "style": "pill-primary"},
  "locale": {"current": "🇺🇸 US", "options": ["🇺🇸 US", "🇨🇦 CA"]},
  "search": {"present": true, "icon": "magnifier"},
  "mobile": {"drawer": true, "search": true, "accordionSections": true}
}
```

#### Footer navigation

The footer is the second menu source. It usually contains multiple link columns ("Our Story / Support / Visit Us"), legal links, social links, and a country/language selector. Treat the column links as a hierarchical menu where each column heading is a top-level menu item and its links are children.

1. Scroll to the bottom of the homepage. Screenshot the footer: `./recon/screens/desktop/_footer-default.png`.
2. `eval` to extract every link in `footer` (or `[role="contentinfo"]`) — group by visual column. Capture column headings as top-level labels and the links inside each column as children.
3. Capture legal/utility links (privacy, terms, accessibility) and social icons separately — these are NOT children of the footer menu; they're chrome the footer component renders.

Write to `./recon/footer-nav.json`:

```json
{
  "menuMachineName": "footer-nav",
  "columns": [
    {"heading": "Our Story", "links": [
      {"label": "Team", "href": "/team"},
      {"label": "Careers", "href": "/careers"}
    ]},
    {"heading": "Support", "links": [
      {"label": "Commercial Support", "href": "/support"},
      {"label": "Contact Sales", "href": "/contact-sales"}
    ]}
  ],
  "legalLinks": [
    {"label": "Privacy Policy", "href": "/privacy"},
    {"label": "Terms of Service", "href": "/terms"}
  ],
  "socialLinks": [
    {"label": "Facebook", "href": "https://facebook.com/..."}
  ],
  "newsletter": {"heading": "Sign up for updates", "placeholder": "Your Email"},
  "copyright": "© 2025 Brand, Inc."
}
```

These two files (`nav.json`, `footer-nav.json`) become the specs for the `navigation` and `footer` components in Step 5, **and** the seed data for the Source menus created in Step 4b. **Always create both. Always.**

### Step 1b — Pages and screenshots

1. Navigate to the URL. List every page reachable from the primary nav (use `nav.json`). Cap at 12.
2. Full-page screenshot each page at **1440px desktop**. Save to `./recon/screens/desktop/<slug>.png`.
3. Full-page screenshot the homepage + 2–3 representative pages at **375px mobile**. Save to `./recon/screens/mobile/<slug>.png`.
4. Write `./recon/pages.json`: `[{"slug": "home", "url": "...", "title": "Home"}, ...]`.

### Step 1c — Parallelism

For larger sites, spawn multiple agent-browser sessions in parallel: `agent-browser --session p1 …`, `agent-browser --session p2 …`. Three sessions cuts capture time by ~60% on 10-page sites. Don't reuse a single session sequentially when you could parallelize.

Do not analyze yet. Capture only.

---

## Step 2 — Decompose into a component catalog

Follow `canvas-design-decomposition` to walk the screenshots and identify components. Classify each:

| Class | Definition |
|-------|------------|
| **Common** | Appears on every page (header **navigation**, footer, breadcrumb) |
| **Shared** | Appears on 2+ pages but not all (cards, CTAs, feature blocks) |
| **Unique** | Appears on **<25%** of pages (specialty heroes, one-off blocks, custom forms) |

**Most important rule in this whole skill:** if two blocks look similar, treat them as **one component with variants**, not two components. Fewer components, more variants → higher fidelity, faster build. This is the single biggest difference between a 65% run and a 99% run.

**Navigation is always its own top-level common component.** It is never folded into a "header" wrapper. The navigation captured in `recon/nav.json` becomes a dedicated `navigation` component (Step 5).

Write `./recon/components.md`, one entry per component, this exact shape:

```markdown
## heroBanner
- **Class:** common
- **Appears on:** home, about, services, contact
- **Screenshot refs:** ./recon/screens/desktop/home.png (region 0-720px), ./recon/screens/desktop/about.png (region 0-560px)
- **Variants:** with-image-right, with-image-left, text-only-centered
- **Props sketch:** eyebrow, title, body, image, primaryCta, secondaryCta, alignment, hasImage
- **Notes:** sticky on scroll = no; image is decorative when alignment=centered
```

Sanity-check the catalog:

- >15 components for a normal marketing site = over-split. Merge.
- A "unique" that's actually a variant of a "shared" = merge.
- Two names that could describe the same thing = merge.

---

## Step 3 — Extract design tokens

Pull computed styles from the live site (the per-page eval in Step 1 already collected the raw data). Save to `./recon/tokens.json`:

```json
{
  "colors": { "primary": "#...", "ink": "#...", "bgMuted": "#...", "border": "#..." },
  "fonts": { "sans": "Inter, ...", "weights": [400, 500, 600, 700, 900] },
  "fontSizes": { "display": 64, "h1": 44, "h2": 36, "h3": 24, "body": 16, "small": 14 },
  "spacing": [4, 8, 12, 16, 24, 32, 48, 64, 96],
  "radii": { "sm": 4, "md": 8, "lg": 16, "pill": 999 },
  "shadows": { "card": "...", "modal": "..." }
}
```

Translate into the Workbench's token files per `canvas-styling-conventions`. Every component must consume tokens. **No hardcoded hex, px, or rem values in any component.** If you reach for a raw value, add a token first.

---

## Step 4 — Images: scan, download, upload via Source MCP

**Three steps. No CLI media commands. No remote URLs in page JSON.**

This is the workflow that actually works on Acquia Source. The Canvas CLI's media upload endpoint (`/canvas/api/v0/media/image/upload`) 503s under load regardless of source format — remote CDN URLs, `placehold.co`, even inline `data:` URLs. Stop trying to push images that way. Use Source MCP `create_media` and reference media by `target_id`.

### Prerequisite

Confirm Source MCP is connected (Step 0.5 check 4). If `mcp__source-mcp__create_media` is not available, stop and ask the user to start the Source MCP server before continuing.

### The workflow

1. **Scan.** Use the per-page image inventory already collected in Step 1 (`./recon/raw/<slug>.json`). Consolidate into `./recon/media.json` as `[{"src", "alt", "w", "h", "pages": [...], "role": "hero|content|icon|logo|bg|misc"}]`. Include `<video>` posters as hero entries. Dedupe by basename.

2. **Download.** Pull every asset to `./public/media/<role>/<safe-filename>` in parallel (Python `concurrent.futures` or shell `xargs -P 8`). Preserve original dimensions. Validate each file: size > 0, image magic bytes present, not an HTML error page. Mark each `recon/media.json` entry with `validated: true | false`. Drop validated:false files from the upload set and record them in `./recon/missing-images.md` so the user knows what's missing.

3. **Upload via Source MCP.** For every validated local file:
   - Call `mcp__source-mcp__create_media` with `bundle: "image"`, descriptive `name`, `filename` (basename), and `metadata: {alt: "..."}`. It returns `target_id` (the MID — a small integer) AND a signed `upload_url`.
   - Upload bytes: `curl -X PUT "<upload_url>" -H "Content-Type: application/octet-stream" --data-binary @<localpath>`. Expect 2xx.
   - Save the mapping to `./recon/media-target-ids.json` keyed by both the original CDN URL and the local file path:
     ```json
     {
       "https://images.example.com/hero.jpg": {"target_id": 123, "localPath": "public/media/hero/hero.jpg"},
       "public/media/hero/hero.jpg": {"target_id": 123, "originalUrl": "https://images.example.com/hero.jpg"}
     }
     ```
   - Parallelize: collect 15–20 `create_media` results, then fire 10-way parallel `curl` PUTs.
   - **Save `recon/media-target-ids.json` after every batch** — Source MCP tokens expire after ~15 min and you must be able to resume without replaying uploads.

### Verification (mandatory)

Before continuing to Step 5:

- Every `validated: true` entry in `recon/media.json` has a matching `target_id` in `recon/media-target-ids.json`.
- Spot-check 3–5 `target_id`s by calling `mcp__source-mcp__list_entities` (filter to media) to confirm they exist on Source.
- Count: total uploaded == total validated. If not, retry the missing ones; if they persist, log to `recon/missing-images.md` and proceed.

### Rule for page JSON

Once Step 4 finishes, every image referenced in `pages/*.json` must use `{"target_id": <id>}` form for Workbench preview AND the Source MCP page assembly (Step 8) passes the **scalar MID integer** directly on image props. **No `https://` URLs in image `src` fields. No `data:` placeholders. No `placehold.co`.**

Sanity-check before any push or MCP page assembly:

```bash
grep -rE 'https?://[^"]+\.(jpg|jpeg|png|webp|gif|svg|avif)|data:image' pages/ && echo "FAIL: page JSON contains image URLs" || echo "OK"
```

Must print `OK`.

---

## Step 4b — Create menus on Source (main + footer) via MCP

**Build the menus before the components that consume them.** The navigation and footer components read menus by `menuMachineName` via JSON:API. If the menus don't exist on Source when the page first renders, the JSON:API call returns empty and the component falls through to its placeholder fallback — destroying parity. Create the menus *before* component build so that by the time pages render in Step 7, the live CMS-linked nav is already there.

This step is **mandatory** for Acquia Source projects. It applies to both Canvas and Nebula on Source. For non-Source local-only Canvas, skip the MCP calls but still create matching menus in Drupal's UI (Structure → Menus) so the dual-source navigation component works in production later.

Reference: `acquia-source-navigation-menus`.

### Prerequisite

Source MCP must be connected (Step 0.5 check 4). The tools you need are:

- `mcp__source-mcp__create_menu` — creates a menu by machine name
- `mcp__source-mcp__create_menu_item` — creates a single menu item, optionally with `parent` for nesting
- `mcp__source-mcp__publish_auto_saves` — publishes the draft items (newly created items are draft auto-saves until published)
- `ReadMcpResourceTool` with `canvas://auto-saves` — fetches the `data_hash` values required by `publish_auto_saves`

### The workflow

#### 1. Create the menu entities

From `./recon/nav.json` and `./recon/footer-nav.json`, read each `menuMachineName`. Call `create_menu` once per menu:

```
create_menu(id="main-nav",   label="Main Navigation",   description="Top navigation mirroring <site>")
create_menu(id="footer-nav", label="Footer Navigation", description="Footer column links")
```

Machine names must be lowercase, alphanumeric, hyphens/underscores only, ≤32 chars. Pick names that won't collide with default Drupal menus (`main`, `footer` are reserved on many installs — prefer `main-nav` / `footer-nav` or a brand prefix).

#### 2. Create the top-level items

For each top-level entry in `nav.json.items` and each `footer-nav.json.columns[].heading`:

```
create_menu_item(
  menu_name="main-nav",
  title="Solutions",
  link="route:<nolink>",   # for parent items without their own URL
  weight=0,
  expanded=true,           # so children render in the megamenu
)
```

- Use `route:<nolink>` for parent items that are megamenus or dropdowns without their own destination URL.
- Use `internal:/path` for items that link directly (e.g. `Blog`, `Contact Sales`).
- Use `https://...` for external links.
- Capture the returned `uuid` from each response — children reference parents by `menu_link_content:<uuid>`.

#### 3. Create the child items (with `parent` ref)

For megamenu/dropdown children in `nav.json` and column links in `footer-nav.json`:

```
create_menu_item(
  menu_name="main-nav",
  title="Hospitality",
  link="internal:/solutions/hospitality",
  parent="menu_link_content:<parent-uuid>",
  weight=0,
)
```

Walk all children in order; bump `weight` to preserve ordering.

#### 4. Publish all auto-saves

`create_menu_item` returns draft auto-saves — they are invisible until published. Fetch the auto-saves resource, collect every `autosave_key` + `data_hash`, then publish in a single batch:

```
ReadMcpResourceTool(server="source-mcp", uri="canvas://auto-saves")
# Returns an array of {autosave_key, data_hash} per item

publish_auto_saves(autosaves=[
  {"autosave_key": "menu_link_content:1:en",  "data_hash": "..."},
  {"autosave_key": "menu_link_content:6:en",  "data_hash": "..."},
  ...
])
```

#### 5. Persist the mapping

Write `./recon/menus.json` with everything needed to wire components later:

```json
{
  "main-nav": {
    "label": "Main Navigation",
    "items": [
      {"title": "Solutions",    "uuid": "...", "id": 1,  "children": [
        {"title": "Hospitality", "uuid": "...", "id": 21}
      ]},
      {"title": "Blog",         "uuid": "...", "id": 11, "children": []}
    ]
  },
  "footer-nav": { ... }
}
```

### Verification (mandatory before Step 5)

- Every `recon/nav.json` top-level item exists as a published `menu_link_content` entity.
- Every megamenu child exists with the correct `parent` reference.
- Every `recon/footer-nav.json` column heading + child is published.
- Visiting `<source-host>/jsonapi/menu_items/main-nav` returns a populated `linkset` (the API is what the navigation component fetches at runtime).

If the verification fails, fix it now. **Components built in Step 5 will not have a live menu to bind to otherwise.**

---

## Step 4c — Content types: model dynamic content as Drupal entities

Some pages on a source site are **content**, not chrome — blog posts, news articles, case studies, products, team bios, knowledge-base entries. Pages where each instance shares one layout but the body changes. Treating those as static page JSON files defeats CMS editability: every typo fix needs a developer. Treating them as Drupal content types lets editors manage instances in the admin UI, and one React component renders any node via a JSON:API + SWR fetch.

**Do not run this for every page.** One-of-a-kind marketing pages (home, pricing, about) belong in `pages/*.json`. Only repeatable, list-rendered content gets a content type.

**Decision is the user's, not yours.** Before any schema work, list the page types you found in Step 1 and ask the user which ones should become Drupal content types. Capture the answer in `recon/content-types.json` as the source of truth.

For each bundle the user opts in, the workflow is:

1. Analyze the page structure → derive a field list (title, deck, hero, body, author, date, category, …)
2. `create_content_type` + `batch_add_fields_to_content_type` via Source MCP (workflow ID is install-specific — read it from `/admin/config/workflow/workflows`, not hardcoded `editorial`/`default`)
3. Scrape every URL for `{title, subtitle, hero, author, publishedDate, bodyHtml, inlineImages}`
4. Convert hero/author images to **jpg** (media:image bundles often reject webp), then `create_media` → `curl PUT` per image — save the slug→MID map after every batch
5. `batch_create_nodes` per bundle, in chunks of ~8, with `path: { alias: '/<bundle>/<slug>' }`
6. Build **one** React component per bundle: prop `slug` → SWR fetch the matching node + a second fetch per media UUID → render
7. Optional: add a content template (`content-templates/node.<bundle>.full.json`) that auto-binds `slug` from `path.alias` so editors don't type slugs (deploy via admin UI — CLI push of templates is blocked on Source)

The detailed workflow, field cheat sheet, and worked code samples for every step live in **[references/step-4c-content-types.md](references/step-4c-content-types.md)** (workflow + decisions) and **[references/content-type-migration.md](references/content-type-migration.md)** (full code: scrape script, React component, content template, gotcha log). Read the workflow file before starting; reach for the code file when you're ready to author.

The most expensive failure modes (workflow ID, srcdoc origin, `?include=` 400s, FormattedText vs background-image, `public://` translation, content-template CLI blocked) are all covered in the "Lessons encoded here" section below — read those before writing any code, even if you've done this before.

---

## Step 5 — Build components as primitives

For each component in `./recon/components.md`, in this order: **navigation → footer → other common → shared → unique**.

Every component must:

- Take **all content via props** — title, body, image, items[], cta, menu structure. No hardcoded copy.
- Take **all design via tokens** from Step 3.
- Cover the variants listed in the catalog using prop-driven variants, not new components.
- Follow the prop discipline below.

### Prop naming discipline (lint-clean from the start)

Canvas's lint rule requires every prop ID to be the exact camelCase of its `title`. Get this right the first time — fixing 16 files later costs an hour.

- Prop ID `itemsHtml` ↔ title `Items Html` ✓
- Prop ID `items` ↔ title `Items (HTML)` ✗ (lint expects `itemsHtml`)
- Prop ID `text` ↔ title `Sub Text` ✗ (lint expects `subText`)
- Never put parentheticals, units, or descriptors in titles. Use a separate Markdown comment for clarification if needed.
- Run `npm run code:fix` (which runs prettier + eslint) **before** `npx canvas validate`. The validate step assumes lint-clean.

### Navigation component (required)

Create `navigation` as its own component folder. Wire it to the **`main-nav` menu created in Step 4b** via `menuMachineName` — that's the primary data source. `recon/nav.json` and `FALLBACK_LINKS` are secondary/Workbench-only sources, in that order. It must support:

- **Logo** (text or image), CTA pill, locale switcher with flag, optional search trigger.
- **Top-level items** with `kind: link | dropdown | megamenu`.
- **Dropdown panels** — hover-open on desktop (with hover-intent delay), click-open on touch; close on `Escape` and outside click.
- **Mega menu panels** — multi-column layout with column headings, link groups, optional promo image/card per panel.
- **Sticky/scroll-shrink behavior** — transparent over hero, solid white once scrolled past a threshold; transition styles per `recon/nav.json`.
- **Mobile drawer** — hamburger triggers full-screen panel; accordion-expand sections for dropdown/megamenu items; search and locale at the bottom.
- **Keyboard navigation** — Tab/Shift+Tab through items, Enter/Space to open a panel, arrow keys to move within an open panel, Escape to close.
- **ARIA** — `aria-haspopup`, `aria-expanded`, `aria-current`; do not put `role="menubar"` on a `<nav>` element (lint rejects interactive roles on non-interactive elements).

#### Required prop shape

Two link sources, in priority order: a Drupal menu by machine name, then a local JSON fallback. This is the canonical Canvas pattern (see `canvas-navigation-components` and `canvas-data-fetching`) and it lets editors swap the live menu without touching code.

```yaml
props:
  properties:
    menuMachineName:
      title: Menu Machine Name
      type: string
      examples:
        - main
    itemsJson:
      title: Items Json
      type: string
      # DO NOT add `contentMediaType: application/json` — Canvas/Source
      # rejects it with "The value you selected is not a valid choice."
      # Only `text/html` is accepted as a contentMediaType value. JSON-as-string
      # works as a plain `type: string` and is parsed in the component.
      examples:
        - '[{"label":"Solutions","kind":"megamenu","columns":[...]}]'
```

#### Required render logic (dual data source + placeholder fallback)

**Critical:** `sortMenu` returns a **tree** where parents carry `_hasSubmenu` and `_children`. Do not flatten — if you map every item to `kind: 'link'`, you lose every megamenu and the user will report "dropdowns don't work" (this has happened on multiple runs). Walk the tree.

```jsx
import { useMemo } from 'react';
import useSWR from 'swr';
import { JsonApiClient, sortMenu } from 'drupal-canvas';

// Hardcoded last-resort megamenu for Workbench preview when no menu and no
// itemsJson are available. Keep the full structure here, not just labels —
// editors should see the real shape in Workbench.
const FALLBACK_LINKS = [
  {
    label: 'Solutions',
    kind: 'megamenu',
    columns: [{ links: [
      { label: 'Hospitality', href: '/solutions/hospitality' },
      { label: 'Corporate',   href: '/solutions/corporate' },
    ]}],
  },
  { label: 'Blog',         kind: 'link', href: '/blog' },
  { label: 'Contact Sales', kind: 'link', href: '/contact-sales' },
];

const client = new JsonApiClient();

const Navigation = ({ menuMachineName, itemsJson, /* ... */ }) => {
  const machineName = (menuMachineName || '').trim();
  const { data, error } = useSWR(
    machineName ? ['menu_items', machineName] : null,
    ([type, id]) => client.getResource(type, id),
  );
  const items = useMemo(() => {
    // 1. Drupal menu — production source. Walk the tree from sortMenu;
    //    parents with _children become megamenus, leaves stay as links.
    if (machineName && data && !error) {
      const sorted = Array.from(sortMenu(data));
      if (sorted.length > 0) {
        return sorted.map((entry) => {
          const url = entry.href || entry.url || '#';
          if (entry._hasSubmenu && entry._children?.length) {
            return {
              label: entry.title,
              kind: 'megamenu',
              columns: [{
                links: entry._children.map((c) => ({
                  label: c.title,
                  href: c.href || c.url || '#',
                })),
              }],
            };
          }
          return { label: entry.title, kind: 'link', href: url };
        });
      }
    }
    // 2. itemsJson — full mega-menu structure authored in the page spec
    const parsed = parseItems(itemsJson);
    if (parsed.length > 0) return parsed;
    // 3. FALLBACK_LINKS — keeps Workbench previews useful when both are empty
    return FALLBACK_LINKS;
  }, [machineName, data, error, itemsJson]);
  // ... render ...
};
```

**Why all three sources are required:**
- The Drupal menu is the **production** source on a live site — editors manage links in Structure → Menus (or via Source MCP per `acquia-source-navigation-menus`). On a fresh site-copy run this menu is created in Step 4b.
- `itemsJson` carries extra structure (columns, blurbs, iconUrls) that Drupal's menu data model doesn't represent. Optional — use only when the megamenu needs detail beyond `{label, href}` per item.
- `FALLBACK_LINKS` keeps Workbench rendering when the page spec hasn't been authored yet — never let the component crash or render blank.

**Hover-gap pitfall:** the megamenu panel typically sits a few pixels below its trigger button. Because absolutely-positioned children don't trigger their parent's `onMouseEnter`, leaving the button schedules a close that fires before the cursor reaches the panel. Fix structurally: put the gap *inside* the panel wrapper (transparent `pt-2`) so the React parent owns both the gap and the panel, and add `onMouseEnter` on the panel that clears the close timer. Don't try to "solve" hover with longer timeouts — it's a structural issue.

After building the component, the corresponding Drupal menu (e.g., `main-nav`) **already exists** on Source because Step 4b created it. Editors can update it via the Drupal UI at `/admin/structure/menu/manage/main-nav` or via Source MCP without touching code.

### Footer component (required, menu-driven)

The footer is the second menu-driven common component. Wire it to the **`footer-nav` menu created in Step 4b** the same way the navigation component is wired — by `menuMachineName`.

Props:

```yaml
props:
  properties:
    menuMachineName:
      title: Menu Machine Name
      type: string
      examples:
        - footer-nav
    legalLinksHtml:    { title: Legal Links Html,    type: string }
    socialLinksHtml:   { title: Social Links Html,   type: string }
    newsletterHeading: { title: Newsletter Heading,  type: string }
    newsletterCta:     { title: Newsletter Cta,      type: string }
    copyright:         { title: Copyright,           type: string }
    countryLabel:      { title: Country Label,       type: string }
```

Render logic mirrors navigation: SWR fetch `menu_items` by `menuMachineName`, walk the tree from `sortMenu`, render top-level entries as column headings and their `_children` as the column links. Legal/social/newsletter/copyright are passed as plain props (or HTML strings) — they're chrome, not menu content.

Same fallback chain: Drupal menu → optional `columnsJson` → small `FALLBACK_COLUMNS` for Workbench. Same dual-render rule applies.

#### component.yml gotcha — invalid contentMediaType

Canvas/Source accepts only `text/html` as a `contentMediaType` value. Other values (e.g. `application/json`, `text/plain`) fail the **component upload** step with:

```
Component upload failed for 1 component: <name>
([props.<prop>.contentMediaType] The value you selected is not a valid choice.)
```

Local `npx canvas validate` may pass — this rule is enforced server-side during push. Catch it before pushing: if you have JSON-shaped or unstructured-string props, omit `contentMediaType` entirely.

### Canvas branch

Author components per `canvas-component-definition` and `canvas-component-metadata`:
- Create `/src/components/<machineName>/component.yml` and the implementation file.
- Use `canvas-component-composability` for slots-vs-props decisions.
- Use `canvas-component-utils` for shared helpers.
- For nav, also follow `canvas-navigation-components` (it covers the Source menu-data side).
- If a component needs real data, follow `canvas-data-fetching`.

After each batch (every 3–4 components), commit with git. Run `npm run code:fix && npx canvas validate`. Fix errors immediately. Do not advance to Step 6 until all components pass clean.

### Nebula branch

Author components per `nebula-component-creation`; validate with `nebula-component-validation` after each component. Same commit-after-each-batch rule applies.

---

## Step 6 — Assemble pages

For each page in `./recon/pages.json`:

### Canvas branch

1. Create the page per `canvas-page-definition`.
2. First element of every page: the `navigation` component. Set `menuMachineName: "main-nav"` (the menu created in Step 4b) — this is the production data source. Do **not** populate `itemsJson` unless the megamenu needs structure the Drupal menu can't represent (icons, blurbs, columns). Same `menuMachineName` value across every page.
3. Bind content using `canvas-content-templates` where appropriate.
4. Compose components in the order they appear on the live site.
5. Pass real content via props. **Image props use `{"target_id": <id>}` (or scalar MID — see Step 8) exclusively**, looked up from `recon/media-target-ids.json` by original URL or local path. **No `https://`, no `data:`, no placeholder URLs in page JSON.** (See [[feedback-no-external-image-urls]] and [[feedback-canvas-media-upload-503]].)
6. Last element: the `footer` component. Set `menuMachineName: "footer-nav"` (the menu created in Step 4b). Pass legal/social/newsletter/copyright as plain props.
7. Save.

Generate pages via a small Python templater (`scripts/build-pages.py` in the project) so the shared header/footer/contact blocks are defined once. The templater reads `recon/media-target-ids.json` and rewrites every image source into `{"target_id": <id>}` form in a single pass. Hand-writing 10 page JSONs by hand is slow and error-prone.

### Nebula branch

1. Scaffold pages per `nebula-node-page-scaffold` or `nebula-workbench-pages`.
2. Compose components in the order they appear on the live site.
3. Pass real content via props.
4. Save.

Homepage first. Then the next 2 most representative pages. Then the rest.

After every 3 pages: commit. Run `npx canvas validate` (or the Nebula equivalent). Must pass clean.

---

## Step 7 — Visual diff loop (THIS is where 99% is won)

The previous bar was 85%. The new bar is 99%. The difference: every single delta gets fixed, every single page, including mobile, and including dropdown/mega-menu interaction states.

**Nebula branch:** run `nebula-visual-verification` per page. Follow its loop exactly. The rubric and anti-patterns below still apply as the final honesty check.

**Canvas branch:** Canvas has no equivalent verification skill, so run the loop below explicitly.

### Workbench full-page screenshot (the trick)

The Workbench UI puts the page inside an iframe, so a normal browser screenshot only captures the visible viewport. Flatten the iframe content into the parent document before screenshotting:

```js
const iframe = document.querySelector('iframe');
const inner = iframe.contentDocument;
inner.querySelectorAll('img[loading="lazy"]').forEach(i => i.loading = 'eager');
inner.documentElement.scrollTop = inner.documentElement.scrollHeight;  // force lazy paints
// then:
document.body.innerHTML = '';
document.body.appendChild(inner.body);
inner.querySelectorAll('style, link[rel="stylesheet"]').forEach(s => document.head.appendChild(s.cloneNode(true)));
```

Then `agent-browser screenshot --full` captures the whole page cleanly.

### The Canvas loop, per page

1. Take a Workbench screenshot at **1440px desktop**. For the homepage and 2 reps, also **375px mobile**.
2. Take screenshots of every navigation interaction state: default, each dropdown open, mega menu open, mobile drawer open, scrolled (sticky transition).
3. Place each Workbench screenshot side-by-side with the matching `./recon/screens/desktop/<slug>.png` (and `_nav-<state>.png` for nav states).
4. Walk top to bottom. Write **every** delta into `./recon/diffs/<slug>.md`. For nav: `./recon/diffs/_nav.md`.
5. For each delta, decide: **component bug** (fixes every page) or **page bug** (this page only).
6. Apply every fix from the diff. No "skip the small ones".
7. Re-screenshot. Re-score. Be honest.
8. If <99, repeat from step 1.

### Diff file format (unchanged)

```markdown
# home — pass 2

## Header / Navigation
- [ ] Logo too small (live ~32px height, ours ~24px). Component bug: navigation.logoSize prop missing.
- [ ] "Solutions" mega menu has 4 columns on live, 3 on ours. Component bug: column-count rendering.
- [ ] Nav background fades to white at 80px scroll; ours stays transparent. Component bug: sticky transition.

## Hero
- [ ] Title font weight 700 on live, 600 on ours. Component bug.
- [x] Background image correct.

## Footer
- [x] Match.

## Mobile
- [ ] Hero stacks differently — image above title on live, below on ours.
- [ ] Mobile drawer doesn't show locale switcher; live does.
```

### Parity scoring rubric (target ≥99)

Score each page out of 100. Award points only if the criterion is fully met. There is no partial credit inside a row.

| Criterion | Weight |
|-----------|--------|
| Header/Navigation: logo, items, dropdowns, mega menu, sticky behavior, mobile drawer all match | 15 |
| Hero / above-the-fold matches (layout, type, image, CTA) | 18 |
| Main content blocks in correct order and proportion | 18 |
| Typography matches (family, size, weight, line-height) | 14 |
| Colors match (text, bg, accent, borders) | 10 |
| Spacing matches (between sections, inside components) | 10 |
| Images correct (right asset, right crop, right size) | 8 |
| Footer matches | 4 |
| Validation/lint clean for the page and the components it uses | 3 |

**Honesty check:** if the diff file has any unchecked box in a criterion, you get **zero** points in that row. "Visually indistinguishable in the side-by-side" is the only thing that counts as a match. A page is done when it scores **≥99** and every box in its diff file is checked.

### When stuck (parity plateaus across 2 passes)

If two diff passes in a row produce the same score on the same page, stop iterating that page and do this:

1. List the 3 largest remaining deltas.
2. For each, identify root cause: missing prop, missing token, missing variant, wrong component choice, or wrong content order on the page.
3. Make the structural change. Re-validate.
4. Resume the loop.

Plateaus mean you're patching symptoms instead of structure. Always fix structure.

### Anti-patterns that drop you below 99

- Eyeballing parity without writing the diff file.
- Marking deltas as "minor" or "polish" to skip them.
- Building a new component to fix a delta when an existing component just needs a new variant.
- Fixing the homepage only and assuming other pages inherit the fixes.
- Skipping mobile diffs.
- Skipping nav interaction-state diffs (hover dropdowns, mega menu, mobile drawer, sticky).
- Calling it done at the first pass.
- Self-grading 99 when the diff file still has unchecked items.

---

## Step 8 — Validate, push, report

**Commit before anything in this step.** `git add -A && git commit -m "feat: site-copy complete pre-push"`.

### Validate

- Canvas: `npm run code:fix && npx canvas validate` — must show `succeeded` for every component and page.
- Nebula: `nebula-component-validation` — must pass clean.

### Push to Source — follow the contract by branch and target

**Acquia Source (Canvas branch with `*.cms.acquia.site` site URL):**

**The Source CLI contract is narrow on purpose.** Acquia Source's `POST /canvas/api/v0/media/image/upload` endpoint is unreliable under load and fails the same way regardless of what you feed it — remote URLs, `placehold.co`, even inline `data:image/png;base64,...` URLs. Every observed run has produced 503 bursts on this endpoint at any non-trivial scale. The only resilient approach is to never call it from the CLI. Pages and media go through Source MCP, full stop.

1. Push **components only**: `npx canvas push --yes --include-pages false --include-content-templates false`. Never `--include-pages`. Pages do not CLI-sync to Source — attempting it produces `elements.<uuid>.type: Invalid input` errors and Source then ships back empty pages on the next pull. (See [[feedback-canvas-pages-no-source-cli-sync]].)
2. Retry on dependency-order failures per `canvas-component-push`.
3. **Never run `npx canvas reconcile-media` against Acquia Source.** It walks `pages/*.json` and POSTs every image prop's `src` to `/canvas/api/v0/media/image/upload`. That endpoint 503s in bursts on Source for **every** source format — including inline `data:image/png;base64,...` URLs. It's the wrong tool for this target. The repo's `pages/*.json` is **Workbench-preview only on Source** — its image `src` values are never read by Source. (See [[feedback-canvas-media-upload-503]] and [[feedback-no-external-image-urls]].)
4. **Pages and their media are assembled exclusively via Source MCP**, per `acquia-source-canvas-pages`. Per page:
   - Menus already exist on Source from Step 4b (`main-nav`, `footer-nav`). Verify they're populated and published before page assembly.
   - Upload images first (Step 4 already did this): every needed image has a MID in `recon/media-target-ids.json`.
   - `create_canvas_page(title, path, description)` → capture `page_id`.
   - **Use `batch_add_components_to_page` — one call per page, not one per component.** Pass the full element array (with props baked in) in a single batch. Components append in array order; omit `index` on each item. This is ~12× fewer MCP round-trips than `add_component_to_page` per element, and Source MCP tokens expire after ~15 min of activity — fewer calls means less chance of a mid-page token expiry. Use the single `add_component_to_page` only when you need to insert a single element into an existing layout at a precise position.
   - **`component_id` must be the `js.`-prefixed machine name** (e.g. `js.navigation`, `js.hero` — not `navigation`). Source rejects unprefixed names with `Unknown component ID`.
   - **Props go in the same batch call** — no separate `update_component_props` round trip needed at creation time. Use `update_component_props` only for later edits.
     - Image props (objects matching the Canvas image schema, e.g. `backgroundImage`, `image`, `logo`) take a **scalar MID integer**, NOT `{"target_id": <id>}` and NOT `{"_provenance": {"target_id": <id>}}`. Pass `backgroundImage: 371`, not `backgroundImage: {target_id: 371}`. Source resolves the scalar MID to the full media reference (src/alt/width/height) automatically.
     - For JSON-string props that contain inline image URLs (e.g. `itemsJson` with `iconUrl`/`imageSrc`), rewrite each URL to the canonical `/media/<mid>` form so the component's plain `<img>` rendering uses the Source-served file.
     - `menuMachineName: "main-nav"` / `"footer-nav"` on navigation/footer components.
   - **Nesting (slots).** For components placed inside a parent's slot, use the batch's `temp_id` mechanism: give the parent `temp_id: "@hero"`, then in children set `parent_instance_id: "@hero"` + `slot: "<slot_name>"`. Parent must appear before children in the array. Temp IDs are batch-scoped.
   - **All-or-nothing batches.** If a single component in the batch fails validation, the whole batch is rejected and Source returns per-component errors. Fix all flagged props in one pass and retry — don't drop the batch into individual calls.
   - `publish_canvas_page(page_id)` when ready. (For unpublished saves on an already-published page, use `publish_auto_saves` instead.)
5. **The repo's `pages/*.json` files are local Workbench previews on Source.** Their image `src` values can be anything Workbench renders — real CDN URLs are fine here for visual fidelity during the diff loop (Step 7). They are NEVER pushed to Source. The Source-side page state lives entirely inside Source, authored via MCP.
6. **Never** run `npx canvas pull` while there is uncommitted authoring in the working tree. `canvas pull` deletes local components that don't exist on the remote and reverts files like `src/global.css`. (See [[feedback-canvas-pull-destructive]].) If a sync seems necessary, commit first.

**Allowed CLI commands against Source (whitelist):**
- `npx canvas push --yes --include-pages false --include-content-templates false` (components only — `--include-pages` defaults to **enabled**, so you must pass `false` explicitly to skip pages on Source)
- `npx canvas validate` (read-only)
- `npx canvas login` (auth)

**Forbidden CLI commands against Source:**
- `npx canvas push --include-pages` — fails on page validation, can wipe Source-side pages
- `npx canvas reconcile-media` — hits the failing media-upload endpoint, never recovers
- `npx canvas pull` (with uncommitted local work) — destructive, deletes local components

**Non-Source Canvas (local Workbench or custom backend that supports page CLI sync):**

1. `npx canvas push --yes`.
2. If page push fails with external-media errors, run `npx canvas reconcile-media`, then `npx canvas push --yes --include-pages`, then `npx canvas pull --include-pages` to sync resolved inputs.

**Nebula:** follow `nebula-component-validation` then the project's push workflow if requested.

If the user did not explicitly ask for a push, **stop and ask** before running any sync command.

### Report

Write `./SITE_COPY_REPORT.md`:

```markdown
# Site Copy Report — <url>

## Branch / Target
Canvas | Nebula  /  Acquia Source | local-only

## Pages
| Page | Parity | Passes |
|------|--------|--------|
| home | 100 | 3 |
| about | 99 | 4 |
| ...

## Components
- Common: navigation, footer (+ breadcrumb if present)
- Shared: <count and names>
- Unique: <count and names>

## Tokens extracted
- Colors: N, Fonts: N, Sizes: N, Spacing: N, Radii: N

## Media
- N assets downloaded to ./public/media/
- N uploaded to Source via create_media (target_ids in recon/media-target-ids.json)

## Navigation
- Items: N (M with dropdown, K with mega menu)
- Sticky/scroll transition: implemented
- Mobile drawer: implemented
- Diff: ./recon/diffs/_nav.md (all states resolved)

## Menus (Source)
- main-nav: N top-level / M children — published, JSON:API serving
- footer-nav: N columns / M links — published, JSON:API serving
- Navigation + Footer components wired via menuMachineName (live CMS-linked)

## Content types (Step 4c, if applicable)
| Bundle | Fields | Nodes imported | React component | Content template |
|--------|--------|----------------|-----------------|------------------|
| blog_post | title, body, subtitle, hero_image, author_name, author_bio, author_photo, published_date, category | 17/17 | src/components/blog_post/ | content-templates/node.blog_post.full.json (validated; deploy via admin UI) |

## Overall parity
- Average: XX%  (target: ≥99%)
- Pages below 99: [list with reason or "none"]

## Source push
- Components pushed: YES/NO at <timestamp>
- Menus created on Source (Step 4b): YES/NO at <timestamp>
- Pages assembled via Source MCP (batch_add_components_to_page): YES/NO at <timestamp>
- Navigation/footer components wired by menuMachineName to live Source menus: YES/NO
```

If any page is below 99%, the skill is **not done**. Loop back to Step 7 for those pages.

---

## Definition of done

- Branch (Canvas or Nebula) was picked deliberately. Remote target (Source vs local) was identified before any push.
- Git is clean, with commits at every batch boundary. No uncommitted authoring exists at any sync command.
- Every page in `./recon/pages.json` scores **≥99** on the rubric.
- Every page has a completed diff file with all items resolved, including mobile and nav interaction states.
- `navigation` component implements logo, top-level items, dropdowns, mega menus, sticky/scroll transition, mobile drawer, keyboard nav, ARIA, locale switch, search trigger — every interaction the live site has.
- Every component validates clean. `npm run code:fix && npx canvas validate` is green.
- All content is prop-driven, all design is token-driven.
- For Acquia Source projects: components pushed via `canvas push` (no `--include-pages`); pages assembled via Source MCP with `batch_add_components_to_page`; **`main-nav` and `footer-nav` menus created on Source in Step 4b (before components) and published**; navigation/footer components bound by `menuMachineName` to those menus so the CMS is the live source of truth.
- For projects with dynamic content (Step 4c): every bundle in `recon/content-types.json` exists on Source with the right field schema; every source URL has a published node with hero media uploaded and referenced by MID; one React component per bundle renders any node via SWR (bare collection + per-media fetch, absolute URLs from `drupalSettings.canvasData.v0.baseUrl`, background-image for hero, `dangerouslySetInnerHTML` for body); content template JSON file exists and validates clean (deploy via admin UI on Source — CLI push of templates is blocked).
- The report exists and reflects reality (no inflated scores).

---

## Lessons encoded here (failure modes that cost real work)

These are the gotchas from past runs. They are the difference between this skill working perfectly and burning hours.

- **`canvas pull` is destructive.** It deletes local `src/components/` files and reverts `src/global.css` and `pages/*.json` to remote state. Never run it on uncommitted work. If a `canvas push` fails, do **not** "diagnose" with `canvas pull` — use `git status`, `npx canvas validate`, and the push error output instead.
- **On Acquia Source, pages don't CLI-sync.** `canvas push --include-pages` returns `elements.<uuid>.type: Invalid input` for every element. The Source push path is: components via CLI, pages via Source MCP (`create_canvas_page` → `batch_add_components_to_page` with the full element array → `publish_canvas_page`). Component IDs in the batch must be `js.`-prefixed (e.g. `js.hero`, not `hero`). Image props take a scalar MID integer (e.g. `backgroundImage: 371`), not `{target_id: ...}`. Use single `add_component_to_page` / `update_component_props` only for surgical edits on an existing page.
- **Commit before sync. Always.** Treat git like load-bearing safety equipment. A 5-second `git add -A && git commit -m wip` is the only recovery path from a destructive pull or a botched push.
- **Prop ID = camelCase(title).** Never put `(HTML)`, units, or parentheticals in titles. Lint will fail and you'll refactor 10+ files. Use clean prop IDs from the start.
- **`npm run code:fix` before `npx canvas validate`.** Validate assumes lint-clean. Reverse the order and you debug formatting errors instead of real problems.
- **Workbench iframe screenshot trick:** flatten `iframe.contentDocument.body` into the outer document before `screenshot --full`. Otherwise you only get the visible viewport.
- **Hero may be a `<video>`, not an `<img>`.** Use `video.poster` as the hero image source when no `<img>` shows up.
- **One combined `eval` per page beats three separate scrapes.** Combine images + text + computed styles + nav structure into a single call. Parallelize across pages with multiple `--session` browsers.
- **Navigation is its own first-class component.** It is never folded into a "header" wrapper, and its dropdown/mega-menu/mobile/sticky states are diffed separately.
- **Navigation must dual-source from a Drupal menu + an itemsJson fallback + `FALLBACK_LINKS`.** Production sites manage links in Drupal (Structure → Menus, or Source MCP via `acquia-source-navigation-menus`). The component reads the menu by machine name via `useSWR + JsonApiClient.getResource('menu_items', menuMachineName) + sortMenu`, falls back to authored `itemsJson` for mega-menu structure, and falls back again to a small static `FALLBACK_LINKS` so Workbench previews are never blank. Expose a `menuMachineName` prop so editors can swap the menu without touching code.
- **`sortMenu` returns a tree, not a flat list.** Each parent carries `_hasSubmenu` and `_children`. The most common navigation bug is mapping `sortMenu` output to `{label, kind: 'link', href}` for every item — that collapses every megamenu/dropdown into a plain link and the user reports "dropdowns don't work." Walk the tree: parents with `_children` become `kind: 'megamenu'`, leaves stay `kind: 'link'`. See Step 5 "Required render logic" for the exact snippet.
- **Build menus before components that consume them.** Step 4b creates `main-nav` and `footer-nav` on Source via MCP (`create_menu` → `create_menu_item` for each top-level + child → `publish_auto_saves`). If you build the navigation component first and try to wire menus later, the dev/preview loop renders the fallback for the entire diff loop and you can't tell whether the JSON:API wiring works until production. Order matters: menus first, then components, then pages.
- **Capture footer navigation too.** Step 1a captures both `recon/nav.json` (main) and `recon/footer-nav.json` (footer columns). The footer is the second menu-driven common component; it gets its own `footer-nav` Source menu and `menuMachineName` binding. Treating the footer as static HTML breaks CMS editability.
- **Megamenu hover-gap is structural, not timing.** If the panel sits below the trigger with any visible margin, `mouseLeave` fires when the cursor enters the gap and the panel closes before the cursor reaches it — because absolutely-positioned children don't trigger their React parent's `onMouseEnter`. Fix: move the gap *inside* the panel wrapper as transparent padding (e.g. `pt-2`), and put `onMouseEnter` on the panel that clears the close timer. Longer timeouts only mask the bug.
- **`contentMediaType: application/json` is rejected on push.** Only `text/html` is accepted server-side. Local `npx canvas validate` does NOT catch this — the failure surfaces during `npx canvas push` as `[props.<prop>.contentMediaType] The value you selected is not a valid choice.` For JSON-shaped or unstructured string props, omit `contentMediaType` entirely and parse the string in the component.
- **Images on Source: scan → download → upload via MCP. Three steps. That's it.** This is the only reliable image path on Acquia Source. (1) Capture image URLs from the live site (Step 1). (2) Download every asset to `public/media/<role>/` and validate magic bytes (Step 4). (3) Call `mcp__source-mcp__create_media` for each validated file, `curl` PUT the bytes to the returned signed URL, store the returned `target_id` in `recon/media-target-ids.json`, and reference media by scalar MID in page assembly (Step 8). Page JSON never contains `https://`, `data:`, or placeholder URLs. (See [[feedback-no-external-image-urls]].)
- **The Source media-upload endpoint is broken at any non-trivial scale, for every source format.** `POST /canvas/api/v0/media/image/upload` 503s in bursts on Acquia Source whether you feed it Contentful URLs, `placehold.co` URLs, or even inline `data:image/png;base64,...` URLs. Retries don't help — the endpoint itself is the failure point. The fix is structural: never invoke any CLI command that walks page-JSON image props on Source. That means `npx canvas push --include-pages` and `npx canvas reconcile-media` are forbidden on Source. Pages and media go through Source MCP exclusively. (See [[feedback-canvas-media-upload-503]].)
- **On Source, `pages/*.json` is Workbench-preview only.** The repo's page JSON image `src` values are never read by Source — Source-side pages live entirely inside Source, authored via MCP. Don't waste cycles rewriting page-JSON image URLs hoping push will accept them. Use whatever Workbench renders best (real CDN URLs are fine for visual fidelity during the Step 7 diff loop) and push pages via MCP, not CLI.
- **Source rejects SVG.** If you do upload via MCP, payloads with `image/svg+xml` are rejected with `Unsupported image type "image/svg+xml". Supported types: image/jpeg, image/png, image/gif, image/webp, image/avif.` Convert to PNG/JPEG/WebP/AVIF before upload.
- **Source MCP tokens expire after ~15 min of activity.** Long sequences — bulk media uploads (100+ `create_media` calls), or assembling many pages one component at a time — will hit a mid-run "MCP server requires re-authorization" error that only the user can resolve (it's a UI re-auth action; the assistant can't trigger it). Two mitigations: (1) **prefer batch tools** so a page is one MCP call, not twelve — `batch_add_components_to_page` for pages, batched parallel calls for media uploads. (2) **Save progress to disk after each unit of work** (e.g. write `recon/media-target-ids.json` after every batch of uploads, write `recon/source-pages.json` after each page publishes) so when a token expires you can resume from exactly where you left off instead of replaying. When you do hit token expiry, stop and ask the user to re-auth — don't retry silently.
- **Don't inflate parity scores.** Live screenshot side-by-side or it doesn't count.
- **Content types are not for every page.** Static one-of-a-kind pages (home, pricing, about) belong in `pages/*.json`. Repeatable, list-rendered content (blog posts, case studies, products, team members) belongs in Drupal content types so editors can manage instances in the admin UI. Step 4c asks the user which is which — never decide unilaterally.
- **Workflow ID is install-specific.** `create_content_type` requires a real workflow machine name and rejects `editorial`, `default`, etc. on Source installs that named their workflow something else (`peleton_workflow`, etc.). Read it from `/admin/config/workflow/workflows/manage/<id>` in the admin UI before calling the MCP tool, or ask the user.
- **MCP token can be bound to the wrong Source.** If `list_entities` returns `canonicalUrl` on a different host than the user is viewing, the MCP session is auth'd to a sibling install. Re-auth via `mcp__source-mcp__authenticate` and complete the new OAuth flow before any writes — otherwise you're scribbling on the wrong site.
- **media:image bundles often reject webp.** Despite the schema response listing `image/webp` as supported, many Source installs configure the bundle's allowed extensions to `jpg, png, gif, jpeg` only. Convert to jpg before `create_media` or the call returns `File extension "webp" is not allowed for media type "image"`. Contentful CDNs respect `?fm=jpg`; native files need ffmpeg/sharp.
- **JSON:API on Canvas is `/api/`, not `/jsonapi/`.** Read the prefix from `drupalSettings.canvasData.v0.jsonapiSettings.apiPrefix` at runtime — assuming the Drupal default leads to 404s.
- **Most `?include=` paths return 400 on Canvas.** The relationship-resolver is brittle, especially for nested includes (`hero_image.field_media_image`) and includes against empty relationships (`author_photo` when no nodes populate it). Don't fight the cascade — fetch the bare collection `/api/node/<bundle>` with no include, then fetch each matched node's hero/author media in a separate `/api/media/image/<uuid>` call. SWR de-dupes; you pay one collection fetch + one media fetch per visible hero.
- **`filter[path.alias]=…` returns 503.** Filtering on the path alias forces a JOIN against `path_alias` that's slow enough to time out on Canvas. Fetch the bare collection and match the slug client-side against `path.alias` (with fallbacks for title, NID, and fuzzy suffix — see Step 4c's "forgiving matcher").
- **The JsonApiClient wrapper from `drupal-canvas` silently swallows errors on this install.** Its `getResourceByPath()` returned HTML instead of JSON; `getCollection()` threw on 400 without surfacing useful info. Use plain `fetch()` with explicit error handling so failures show the actual HTTP status — that's the fastest path to diagnosing API issues.
- **Srcdoc iframes have no usable origin.** Canvas Workbench's preview iframe uses `<iframe srcdoc="…">` for fast live updates. The resulting document has URL `about:srcdoc`, opaque or inherited origin, and **broken relative URLs**. Any `fetch('/api/…')` or relative image URL inside the component either fails outright or routes through Canvas's `/canvas/template/.../component/null/…` asset rewriter (which 303s to nowhere). Fix: read the real Source origin from `window.drupalSettings.canvasData.v0.baseUrl` and prefix it to every URL the component generates — both API calls and image `src`/`background-image` values.
- **Canvas's `<Image>` and `<FormattedText>` components require `?alternateWidths=…` or a custom loader.** They wrap `<img>` tags with a responsive-image processor designed for Canvas-managed media — plain CDN URLs and `/sites/default/files/...` paths don't satisfy the contract, so the image silently fails to render and the console warns "Responsive image generation failed." Two workarounds: (1) render hero/author photos as CSS `background-image` on a `<div>` (the processor only targets `<img>` tags), and (2) render body HTML via `dangerouslySetInnerHTML` instead of `<FormattedText>` so inline body images escape the wrapper.
- **Translate `public://` stream URIs to `/sites/default/files/`.** JSON:API sometimes returns the unresolved Drupal stream URI on file entities instead of the resolved public path. The component must translate `public://2024-12/file.jpg` → `/sites/default/files/2024-12/file.jpg` (and `private://` → `/system/files/`) before constructing the absolute URL.
- **Canvas's field-link chip only surfaces stored leaf properties, not computed values.** When you give a prop `type: string`, the chip dropdown offers text-shaped fields (Title, Path) — but NOT the URL of an image field. To make image props field-bindable in the UI, declare them with `$ref: json-schema-definitions://canvas.module/image`. Canvas internally knows how to resolve a media reference into the full `{src, alt, width, height}` schema — the chip's "Hero Image → Image" option will write the resolved object into the prop. If you only need a URL (not the full image schema), keep the prop as `string` and rely on the SWR fetch of the node's media field via the slug binding.
- **List/typed-field values arrive wrapped as `{value: "x"}`.** `list_string`, `datetime`, and a few other types come through JSON:API with their value nested under a `value` key. Read `obj.value` before formatting or label lookup — passing the wrapper through string concatenation renders `[OBJECT OBJECT]` in the UI.
- **Be forgiving about what the slug prop receives.** Editors bind props to entity fields via Canvas's field-link chip, but Canvas doesn't enforce semantic compatibility — they may bind slug to Title (the H1 text), Path (the URL alias), or NID (a numeric ID). A robust component matches in order: `path.alias === '/<bundle>/<slug>'` → case-insensitive title match → numeric NID match → fuzzy `endsWith('/<slug>')`. Whichever field the editor picks resolves to the right node.
- **Content templates can't be CLI-pushed to Acquia Source.** The `page_template:administer` route rejects client-credentials OAuth ("authentication method is not allowed on this route") — only user-delegated auth (browser OAuth code flow) is accepted. `npx canvas push --include-content-templates` will fail with an `invalid_scope` or auth-method error. Either author the template in the Drupal admin UI (Structure → Canvas → Content templates) or use a user-delegated `CANVAS_ACCESS_TOKEN`. Keep the local JSON file regardless — `npx canvas validate` validates it and it's the source of truth.

---

## Trigger phrases

- "Copy [url] into Workbench"
- "Recreate [url] in Source"
- "Site copy of [url]"
- "Rebuild [url] as Source components"
- "Clone [url] into Workbench"
- "Match [url]'s design in Source"
- "Import all blog posts / articles / case studies from [url] into Source"
- "Migrate [url]'s content into Drupal content types"
- "Make a content type for [bundle] from [url] and import the entries"
- Any request to recreate, clone, or visually match a live URL's design as Source components
- Any request to migrate dynamic/list content (blog, news, case studies, products) from a live site into Drupal content types with a React component that renders them via SWR
