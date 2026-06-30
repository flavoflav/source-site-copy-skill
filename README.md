# site-copy

> Copy a live website into Acquia Source Workbench as native components, pages, menus, and media — at ≥99% visual parity, with editor-ready CMS wiring.

`site-copy` is a procedural skill for Claude that turns "copy this URL into Source" into a deterministic, eight-step pipeline. The output isn't a snapshot or an export — it's real Source artifacts that an editor can immediately log in and modify.

The skill works against both **Canvas** and **Nebula** projects, on both **Acquia Source** and local-only targets. It auto-detects which by inspecting your project.

---

## What it produces

When the skill finishes a clean run on an Acquia Source Canvas project:

**On disk:**

- `recon/` — full reconnaissance archive (per-page JSON, desktop and mobile screenshots, navigation interaction-state screenshots, component catalog, design tokens, media manifest, MID mapping, menu mapping, per-page diff files)
- `public/media/` — every downloaded image, validated
- `src/components/<name>/` — every component with `component.yml` and implementation, lint-clean and validated
- `pages/*.json` — Workbench preview specs
- `SITE_COPY_REPORT.md` — per-page parity table, component counts, push log

**On Source:**

- Components pushed and validated
- `main-nav` and `footer-nav` menus created and published, serving via JSON:API
- Canvas pages assembled via Source MCP with components in the right order, image props as scalar MIDs, and `menuMachineName` bindings wiring navigation and footer to the live menus
- Published pages, ready to serve

Editors can log in, edit a menu item, swap an image, change body copy, and see it reflected immediately. Nothing is hardcoded into static HTML.

---

## Installation

`site-copy` is meant to be run from inside a **Nebula-created local project directory**. The Nebula project scaffolding ships with every dependent Acquia Source authoring skill (`canvas-design-decomposition`, the full `canvas-component-*` suite, `acquia-source-canvas-pages`, the `nebula-*` skills, etc.) already installed — so the only thing you need to add is the three `.skill` bundles from this repo:

```bash
# From inside your Nebula-created project directory
unzip -d ~/.claude/skills/ site-copy.skill
unzip -d ~/.claude/skills/ agent-browser.skill
unzip -d ~/.claude/skills/ local-power-tools.skill

# Verify
ls ~/.claude/skills/site-copy/SKILL.md \
   ~/.claude/skills/agent-browser/SKILL.md \
   ~/.claude/skills/local-power-tools/SKILL.md
```

All three are mandatory. `site-copy` halts at Step 0 if either of the other two is missing.

If you're running outside a Nebula-created directory and Step 0 reports a missing sub-skill, install that skill from the Acquia Source skill library before retrying.

### Install the underlying CLIs

`agent-browser` is a Node binary; `local-power-tools` is a curated set of CLIs (`ast-grep`, `difft`, `sd`, `comby`, `scc`, `yq`, `shellcheck`, `hyperfine`, `watchexec`, `vips`, `odiff`, `aria2c`, `htmlq`, `exiftool`, `biome`). The repo ships a universal installer that handles all of them:

```bash
./local-power-tools-install.sh             # install everything that's missing
./local-power-tools-install.sh --list      # show every tool and its current status
./local-power-tools-install.sh --dry-run   # print the commands without running them
./local-power-tools-install.sh --help      # all flags (--only, --skip, --yes, --no-agent-browser)
```

The installer auto-detects your platform — macOS (Homebrew), Debian/Ubuntu (apt), Fedora/RHEL (dnf), Arch (pacman) — and falls back to `cargo` or `npm` for tools that aren't packaged everywhere. Tools already on `PATH` are skipped. After installing `agent-browser`, it runs `agent-browser install` once to fetch a Chrome-for-Testing build.

#### Full list of what the installer covers

|  # | Tool          | macOS (brew) | Debian/Ubuntu (apt)      | Fedora/RHEL (dnf)      | Arch (pacman)         | Fallback                       |
|---:|---------------|--------------|--------------------------|------------------------|-----------------------|--------------------------------|
|  1 | ast-grep      | ast-grep     | —                        | —                      | ast-grep              | `cargo install ast-grep`       |
|  2 | difft         | difftastic   | difftastic               | difftastic             | difftastic            | `cargo install difftastic`     |
|  3 | sd            | sd           | sd                       | —                      | sd                    | `cargo install sd`             |
|  4 | comby         | comby        | —                        | —                      | —                     | manual binary release          |
|  5 | scc           | scc          | —                        | —                      | scc                   | `go install …/scc/v3@latest`   |
|  6 | yq            | yq           | yq                       | yq                     | go-yq                 | binary release                 |
|  7 | shellcheck    | shellcheck   | shellcheck               | ShellCheck             | shellcheck            | manual                         |
|  8 | hyperfine     | hyperfine    | hyperfine                | hyperfine              | hyperfine             | `cargo install hyperfine`      |
|  9 | watchexec     | watchexec    | watchexec                | —                      | watchexec             | `cargo install watchexec-cli`  |
| 10 | vips          | vips         | libvips-tools            | vips-tools             | libvips               | manual                         |
| 11 | ffmpeg        | ffmpeg       | ffmpeg                   | ffmpeg                 | ffmpeg                | manual                         |
| 12 | odiff         | odiff-bin    | —                        | —                      | —                     | `npm i -g odiff-bin`           |
| 13 | aria2c        | aria2        | aria2                    | aria2                  | aria2                 | manual                         |
| 14 | yt-dlp        | yt-dlp       | yt-dlp                   | yt-dlp                 | yt-dlp                | binary release                 |
| 15 | htmlq         | htmlq        | —                        | —                      | —                     | `cargo install htmlq`          |
| 16 | exiftool      | exiftool     | libimage-exiftool-perl   | perl-Image-ExifTool    | perl-image-exiftool   | manual                         |
| 17 | biome         | biome        | —                        | —                      | —                     | `npm i -g @biomejs/biome`      |
| 18 | agent-browser | —            | —                        | —                      | —                     | `npm i -g agent-browser` + `agent-browser install` |

A `—` means there's no native package on that platform; the installer uses the fallback in the last column. Run `./local-power-tools-install.sh --list` to see the exact command the installer would run on your machine for each tool.

**`ffmpeg` + `yt-dlp`** are the video pipeline. They don't discover videos themselves — `agent-browser` does that by executing the page's JavaScript and reading the resolved `<video>` `currentSrc` / `<source>` URLs (modern marketing pages render video tags in JS, so static HTML scrapes find nothing). Once `agent-browser` hands over a real video or HLS/DASH manifest URL, `yt-dlp` downloads it (handling adaptive bitrate and retries), `ffprobe` (ships with `ffmpeg`) returns structured metadata for the Source `media:video` bundle decision, and `ffmpeg` extracts a poster frame when the page didn't declare one. Skill-side wiring for this lands in a future site-copy update.

---

## Prerequisites

The skill checks for each of these and stops if any are missing.

### Required

1. **A Canvas or Nebula project** to work in (existing or freshly scaffolded — the skill won't initialize from nothing).
2. **A clean git working tree.** The skill commits after every batch and refuses to start on dirty state. This is its only recovery path from a destructive sync command.
3. **Source MCP connected** with these seven tools available: `create_media`, `create_canvas_page`, `batch_add_components_to_page`, `publish_canvas_page`, `create_menu`, `create_menu_item`, `publish_auto_saves`. Required for any Acquia Source target — there is no CLI fallback that works reliably.
4. **Run from inside a Nebula-created local project directory** — the dependent Acquia Source authoring skills ship with that scaffolding. If you're not in a Nebula project, see [Installation](#installation) for the manual fallback.
5. **The live site URL.** Publicly accessible, or accessible from wherever `agent-browser` is running.

### Highly recommended local tools

Two skills + their underlying CLIs make the skill dramatically faster and more reliable. Install these into your local environment **before** running `site-copy` on a real engagement.

#### `agent-browser`

The skill's primary browser-automation driver. Used in Step 1 (capture) and Step 7 (visual diff loop) for navigating the live site, taking full-page screenshots at desktop and mobile widths, extracting computed styles, capturing navigation interaction states, and running pixel-diffs between the Workbench build and live.

This is the **preferred** browser automation tool for `site-copy` — not the Claude in Chrome extension. The daemon-backed CLI is faster across multi-step workflows because the browser stays open between commands, and it parallelizes cleanly (three `--session` browsers in parallel cuts capture time by ~60% on a 10-page site).

Without `agent-browser`, the capture step degrades sharply — the skill falls back to less reliable scraping methods that miss megamenu hover states, sticky-scroll transitions, and mobile drawer content.

#### `local-power-tools`

A curated toolbox of fast, structured CLI replacements for common Unix defaults. Several are load-bearing for `site-copy`:

| Tool | Used for | Step |
|------|----------|------|
| **`vips`** | Image conversion, resizing, format swaps — **especially SVG → PNG/WebP/AVIF** since Source rejects `image/svg+xml` | Step 4 |
| **`odiff`** | Pixel-level screenshot comparison with measured parity score and diff image output | Step 7 |
| **`scc`** | Counting components, lines of code, complexity at the end of a run | Step 8 (report) |
| **`ast-grep`** | Structural code search and refactor when fixing prop-naming or token-consumption issues across many components | Step 5 |
| **`difft`** (difftastic) | Syntax-aware diffs when reviewing component changes between diff-loop passes | Step 7 |
| **`sd`** | Literal/regex find-and-replace when rewriting image URLs to MID form in page JSON | Step 6 |
| **`hyperfine`** | Benchmarking the capture step on larger sites | Step 1 |

The Step 7 diff loop in particular benefits from `odiff` — it produces a numeric parity score and a visual diff image, which is much more honest than eyeballing side-by-side screenshots.

Install both via their respective project READMEs. The `site-copy` skill detects which tools are present and adjusts its commands accordingly.

---

## Usage

On a Canvas or Nebula project with a clean git tree and Source MCP connected, ask Claude to copy a specific URL into Workbench:

```
Copy https://example.com into Workbench
```

Or any of:

```
Recreate https://example.com in Source
Clone https://example.com for Canvas
Rebuild https://example.com as Source components
Match https://example.com's design in Source
```

The skill triggers on phrases naming a URL and a Source-side build target. You don't need to invoke it by name.

---

## How it works

Eight numbered steps plus two preflight gates. Each step writes its output to disk so the next step can read from it — which means crashes and token expiries don't lose more than the current step's work.

### Step 0 — Branch detection and sub-skill loading

The skill inspects your project to determine Canvas vs. Nebula and Acquia Source vs. local-only target. This determines the push contract in Step 8.

### Step 0.5 — Preflight

Four checks that take seconds and prevent the most expensive failure modes:

- Git status is clean
- Commit checkpoints will fire after every batch
- The push contract is stated to you out loud
- Source MCP connectivity is verified

If any check fails, the skill stops and asks.

### Step 1 — Capture

For each page reachable from the primary navigation (capped at 12), `agent-browser` captures everything needed in one pass: images and natural dimensions, hero `<video>` posters as fallback, computed styles for tokens, content text, and navigation structure. Full-page screenshot at 1440px desktop, plus 375px mobile for the homepage and 2–3 representative pages.

Parallelizes across multiple `agent-browser` sessions for larger sites.

**Output:** `recon/raw/<slug>.json` per page, plus screenshots.

### Step 1a — Navigations (main + footer)

Navigation gets captured separately because static DOM scrapes miss interaction state. For each nav root that opens a panel, the skill hovers it, waits 400ms for animations, screenshots the open state, and snapshots the panel DOM. Same treatment for mobile drawer (closed and open) and sticky behavior at 600px scroll.

For the footer: column headings as top-level menu items, links as children, legal/social/newsletter as separate chrome.

**Output:** `recon/nav.json`, `recon/footer-nav.json`, interaction-state screenshots. These drive both the navigation/footer components in Step 5 and the Drupal menus in Step 4b.

### Step 2 — Decompose

Walks the screenshots and identifies components, classifying each as Common (every page), Shared (2+ pages), or Unique (<25% of pages). The most important rule: **if two blocks look similar, treat them as one component with variants, not two components.**

**Output:** `recon/components.md`.

### Step 3 — Tokens

Computed styles from Step 1 get distilled into `recon/tokens.json` — colors, fonts, sizes, spacing, radii, shadows — and translated into the project's token files. Every component built afterward consumes these tokens. No hardcoded hex, px, or rem values.

### Step 4 — Images: scan → download → upload via Source MCP

Source's CLI media-upload endpoint is unreliable at scale. The skill never uses it. Instead:

1. **Scan** — consolidate per-page image inventory into `recon/media.json`, tagged by role.
2. **Download** — pull every asset to `public/media/<role>/`, validate each (size, magic bytes, not an HTML error page). `vips` handles SVG → PNG/WebP/AVIF conversion since Source rejects SVG.
3. **Upload via Source MCP** — for every validated file, `create_media` (returns target_id MID + signed upload URL), `curl -X PUT` the bytes, save mapping to `recon/media-target-ids.json` after every batch.

After this step, every image is referenced by a Source MID, not a remote URL. A grep-based sanity check verifies no `https://`, `data:`, or placeholder URLs remain in page JSON.

### Step 4b — Menus on Source (before components)

Build menus before components that consume them. Otherwise the dev/preview loop renders fallback content the entire diff loop and you can't tell whether production wiring works until ship.

- `create_menu` for `main-nav` and `footer-nav`
- `create_menu_item` for each top-level entry, capturing UUIDs
- `create_menu_item` for children, referencing parents by `menu_link_content:<parent-uuid>`
- Single `publish_auto_saves` call to publish the batch

**Output:** `recon/menus.json`, published menu_link_content entities on Source. Verified by hitting `/jsonapi/menu_items/main-nav` and confirming a populated linkset.

### Step 5 — Build components

Fixed build order: navigation → footer → other common → shared → unique. Every component takes all content via props and all design via tokens.

The navigation component uses a three-source pattern with strict priority:

1. **Drupal menu** by `menuMachineName` — production source, read via `useSWR + JsonApiClient.getResource + sortMenu`
2. **`itemsJson` prop** — optional, carries structure (icons, column blurbs) Drupal's menu model can't represent
3. **`FALLBACK_LINKS` constant** — keeps Workbench previews from going blank

After each batch, `npm run code:fix && npx canvas validate`. Errors get fixed immediately. The skill doesn't advance to Step 6 until everything passes clean.

### Step 6 — Assemble pages

Each page gets a JSON file: navigation first (`menuMachineName: "main-nav"`), content components in live-site order, footer last (`menuMachineName: "footer-nav"`). Image props look up MIDs from `recon/media-target-ids.json`.

A small Python templater (`scripts/build-pages.py`) gets generated so shared blocks are defined once and image references get rewritten into MID form in one pass.

### Step 7 — Visual diff loop

This is where 99% parity gets won.

For each page: full-page Workbench screenshot at 1440px (and 375px mobile for representatives), screenshots of every nav interaction state, side-by-side with the matching live screenshots. `odiff` produces a numeric parity score and a diff image; the skill walks top-to-bottom and writes every delta into `recon/diffs/<slug>.md` as a checklist.

Each delta gets classified: component bug (fixes every page) or page bug (this page only). Apply fixes, re-screenshot, re-score.

Strict 100-point rubric, no partial credit within rows: 15 navigation, 18 hero, 18 main content, 14 typography, 10 colors, 10 spacing, 8 images, 4 footer, 3 validation/lint-clean. Any unchecked box in the diff file zeroes that row.

A page is done when it scores ≥99 and every box is checked.

### Step 8 — Validate, push, report

After commit, validate everything (`npx canvas validate` must show `succeeded` for every component and page) and push by contract.

**On Acquia Source:**

- **Components** push via `npx canvas push --yes --include-pages false --include-content-templates false`
- **Pages** assemble via Source MCP: `create_canvas_page` → `batch_add_components_to_page` (one batch per page) → `publish_canvas_page`
- **Image props** in the batch take a scalar MID integer (`backgroundImage: 371`), not `{target_id: 371}`
- **Component IDs** must be `js.`-prefixed (`js.navigation`, not `navigation`)
- **Slotted children** use batch-scoped `temp_id` references

**Forbidden on Source:** `canvas push --include-pages`, `canvas reconcile-media`, `canvas pull` with uncommitted local work.

**On local-only Canvas:** `npx canvas push --yes` for both components and pages, `canvas reconcile-media` for media if needed.

Final output: `SITE_COPY_REPORT.md` — per-page parity table, component breakdown, token counts, media counts, navigation summary, push log with timestamps. If any page is below 99%, the skill is not done and loops back to Step 7.

---

## What to expect during a run

**Time.** A normal 8–10 page marketing site takes at least 45 minutes, sometimes longer depending on the site design. The Step 7 diff loop is the longest phase; most pages need at least two passes to hit 99%.

**Conversation.** The skill pauses and asks at specific gates: confirming the push contract, confirming branch detection when ambiguous, asking you to start the MCP server if disconnected, asking how to handle SVGs, asking permission before any sync command. You don't need to babysit, but be reachable.

**MCP token expiry.** Source MCP tokens expire after ~15 minutes of activity. The skill persists progress to disk after every batch and survives this — but only you can re-auth when it happens. The skill will stop and ask.

**The diff loop is honest.** If the skill says a page is at 87%, it's at 87%. The rubric is strict and the diff file is the evidence. To ship at less than 99%, tell the skill up front and it'll shorten the loop accordingly.

---

## Scope limits

A few things the skill doesn't currently handle well:

- **Custom scroll-driven animations, WebGL heroes, complex video orchestration** — the recon step captures what `agent-browser` can capture; bespoke choreography may need manual authoring.
- **Authentication-gated content** — set up an authenticated browser session in advance and point `agent-browser` at it.
- **Sites that change between captures** — capture once and treat that snapshot as source of truth for the run.
- **Sites larger than 12 pages** — that's the default discovery cap. Run in batches or extend the cap explicitly.

---

## FAQ

**Will it overwrite work in my existing project?**
Only if your git tree is dirty when it starts, and it refuses to start in that state. On a clean tree, it commits after every batch — worst case is `git reset` back to a known state.

**Can I run it without Source MCP?**
Against a local-only Canvas project, yes. Against Acquia Source, no. The CLI media-upload endpoint isn't reliable enough as the primary path, and pages don't CLI-sync to Source at all.

**Can I run just part of it?**
Yes. Artifacts at each step persist to disk, so you can start at Step 1 and stop after Step 7 without pushing, or skip recon and use existing `recon/` files. The skill is resumable.

**What if 92% is close enough?**
Talk to the skill about it. The 99% bar is what it enforces by default because that's what "ready to push without manual cleanup" actually means. Different engagements have different bars — say so up front.

**How is this different from a manual site copy?**
The mechanical parts are similar. The difference is the contracts that make a Source-side copy actually ship: menus before components, MCP for pages and media, components-only via CLI, scalar MIDs in batch calls, dual-source navigation wiring. Those are what partners most often get wrong on a first engagement.

---

## Trigger phrases

- "Copy [url] into Workbench"
- "Recreate [url] in Source"
- "Site copy of [url]"
- "Rebuild [url] as Source components"
- "Clone [url] into Workbench"
- "Match [url]'s design in Source"
- Any request to recreate, clone, or visually match a live URL's design as Source components

---

## Feedback

Rough edges found on real engagements are the most valuable input for the next version of this skill. If you hit something it doesn't handle well — or handles surprisingly well — capture the case and pass it along.
