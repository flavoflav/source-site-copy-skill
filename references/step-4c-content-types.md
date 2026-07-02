# Step 4c — Content types: model dynamic content as Drupal entities

This is the workflow companion to **Step 4c** referenced from SKILL.md. Open it whenever the user wants to migrate dynamic/repeatable content (blog posts, news articles, case studies, products, team bios, knowledge-base entries) from a source site into Drupal content types so editors can manage instances in the admin UI and a single React component renders any node via JSON:API + SWR.

Pair this file with [content-type-migration.md](content-type-migration.md), which holds the deep code samples (full scrape script, full React component, content template) and the cross-referenced failure-mode log.

---

## Why this step exists

Some pages on a source site are **content**, not chrome. Blog posts, news articles, case studies, product pages, team bios, knowledge-base entries — pages where each instance shares one layout but the body changes. Treating those as static page JSON files defeats CMS editability: every typo fix needs a developer. Treating them as Drupal **content types** with **nodes** lets editors manage them in the admin UI, and one React component renders any instance via a JSON:API fetch.

This step is where the skill graduates from "visual clone" to "real CMS site." **Do not run it for every page.** Most marketing pages (home, pricing, about) are one-of-a-kind and belong in `pages/*.json`. Only repeatable, list-rendered content goes here.

---

## When to use it — ask the user

Before writing any schema, list the page types you discovered in Step 1 and **ask the user which ones should become content types**. The user is the authority on editorial workflow.

Phrase it like:

> I found these page types on the site:
> - 17 blog posts at `/blog/<slug>` — same template, different bodies → likely content type
> - 8 case studies at `/case-studies/<slug>` — same template → likely content type
> - 4 product pages at `/products/<slug>` — same template → maybe content type
> - Home, About, Pricing, Contact → one-off, stay as static pages
>
> Which of these should be Drupal content types so editors can manage them in the admin UI? Anything I missed?

Capture the user's answer in `./recon/content-types.json` as the source of truth:

```json
[
  {"bundle": "blog_post", "label": "Blog Post", "urlPattern": "/blog/<slug>", "exampleUrls": [...]},
  {"bundle": "case_study", "label": "Case Study", "urlPattern": "/case-studies/<slug>", "exampleUrls": [...]}
]
```

---

## The workflow (per content type)

For every entry in `recon/content-types.json`, run this loop. Steps 1–3 are setup-once; steps 4–6 are per-node.

### 1. Analyze the page structure → field list

Open 2–3 example pages from the bundle's `exampleUrls`. Walk each one top to bottom and list every distinct content slot. Common shape:

| Slot                | Field type        | Why                                            |
|---------------------|-------------------|------------------------------------------------|
| Title (H1)          | built-in `title`  | every node has one                             |
| Deck / subtitle     | `string` (≤512)   | one-line lead under the H1                     |
| Hero image          | entity_reference → media:image | large image at top, swappable      |
| Body (rich HTML)    | built-in `body`   | the article — paragraphs, H2s, inline imgs    |
| Author name         | `string`          | byline                                         |
| Author bio          | `string_long`     | paragraph about the author                     |
| Author photo        | entity_reference → media:image | headshot                            |
| Published date      | `datetime`        | sortable, displayable                          |
| Category            | `list_string`     | taxonomy-lite — Travel & Hospitality, etc.    |
| Tags                | entity_reference → taxonomy_term | optional, for filtering          |

Save the analysis to `./recon/content-types/<bundle>/fields.json`. Adding fields later costs migrations and re-imports — get this right up front by inspecting at least three example pages, including edge cases (long titles, multiple images, no author).

### 2. Create the content type + fields via Source MCP

The workflow ID is install-specific (it's NOT `editorial` or `default` on every install). Read it from the admin UI at `/admin/config/workflow/workflows` or ask the user — the URL contains the machine name (`…/workflows/manage/<machine_name>`).

```
create_content_type(
  machine_name="blog_post",
  label="Blog Post",
  workflow="<install_workflow>",        # e.g. peleton_workflow
  options={create_body_field: true, help: "Editorial article."}
)
```

Then add every non-built-in field in **one** `batch_add_fields_to_content_type` call so storage is created in order. For entity_reference to media:

```yaml
- field_name: hero_image
  field_type: entity_reference
  label: Hero Image
  storage_settings: { target_type: media }
  field_settings:
    handler: default:media
    handler_settings:
      target_bundles: { image: image }
```

For list_string enums (categories), put the machine→label map in `storage_settings.allowed_values`:

```yaml
- field_name: category
  field_type: list_string
  label: Category
  storage_settings:
    allowed_values:
      travel_hospitality: "Travel & Hospitality"
      workplace_wellness: "Workplace Wellness"
```

Verify by reading the schema back: `ReadMcpResourceTool(server="source-mcp", uri="drupal://content-types/<bundle>")` — confirm every field you added is in `properties`.

### 3. Scrape content + images for every URL

Do this in **two stages** (full scripts in [content-type-migration.md](content-type-migration.md#scrape-pipeline)): a browser stage that renders each URL and dumps the resolved HTML to `./recon/<bundle>/html/<slug>.html`, then a **BeautifulSoup extraction stage** (`scripts/extract_<bundle>.py`) that parses that HTML into the structured fields below. Keep extraction in bs4, not in the browser — it tolerates malformed markup, and you can re-tune a selector and re-run across the whole corpus offline without re-scraping. The fields to extract:
- `title` (H1)
- `subtitle` (the deck — usually a P sibling of H1)
- `hero` (first significant img inside `article` or `main` with naturalWidth ≥ 600)
- `author` (a block titled "About the author" or similar — usually contains a heading + bio paragraph + headshot)
- `publishedDate` (a `<time>` element, or first `Month DD, YYYY` regex match)
- `bodyHtml` (the inner HTML of the largest container with ≥2 `<p>` and ≥1 `<h2>`)
- `inlineImages` (all `<img>` inside the body for follow-up upload if you want them on Source too)
- `category` (breadcrumb or section label from the index page)

The bs4 stage writes each post to `./recon/<bundle>/raw/<slug>.json`. Run the browser dump concurrently across multiple sessions — the index alone has all the URLs to walk — then run the single bs4 pass over the dumped HTML.

The full two-stage pipeline (browser dump + the BeautifulSoup extractor with the subtitle/hero/body/author heuristics) is in [content-type-migration.md](content-type-migration.md#scrape-pipeline).

### 4. Upload hero + author photos via Source MCP

The bundle's allowed extensions vary by install. Many Source Drupal sites restrict media:image to **jpg/png/gif only** — **webp is rejected on push** despite the schema implying it's accepted. Download images as jpg (Contentful supports `?fm=jpg`; other CDNs respond to `Accept: image/jpeg`). After download, validate the real format with `exiftool -FileType -T <dir>/*` — an `HTML`/`TXT` FileType is an error page, and a non-JPEG FileType behind a `.jpg` extension gets converted with `vips copy in out.jpg[Q=85]` before upload.

For each validated file:

```
create_media(
  bundle="image",
  name="Blog hero — <post title>",
  filename="<slug>.jpg",
  metadata={alt: "<post title or hero alt>"}
)
# returns {mid, upload_url}

curl -X PUT "<upload_url>" -H "Content-Type: application/octet-stream" --data-binary @<localpath>
```

Save the slug→MID map to `./recon/<bundle>/media-target-ids.json` after every batch — Source MCP tokens expire after ~15 min, and you must be able to resume without re-uploading. Parallelize: 10–15 `create_media` calls in flight at once, then parallel `curl` PUTs.

Full download + upload pipeline code in [content-type-migration.md](content-type-migration.md#media-upload-pipeline).

### 5. Import nodes via `batch_create_nodes`

Build one node payload per scraped post:

```js
{
  title: data.title,
  moderation_state: 'published',
  body: { value: cleanedBodyHtml, format: 'filtered_html' },
  subtitle: data.subtitle,
  author_name: data.author?.name,
  category: data.categoryKey,
  hero_image: { target_id: heroMid },     // entity reference: { target_id }
  published_date: '2024-12-17',           // YYYY-MM-DD for datetime(date) fields
  path: { alias: `/blog/${slug}` },
}
```

Drop null/empty fields rather than sending nulls — JSON:API can reject empty entity references.

Split into batches of ~8 if a single request would exceed reasonable payload size, and call `batch_create_nodes` once per batch:

```
batch_create_nodes(bundle="blog_post", nodes=[...], options={return_details: false})
```

Each batch returns total/successful/failed counts. On failure, the response details which node's which field failed — fix and retry that batch.

Verify with `list_entities(entity_type="node", bundle="blog_post", limit=…)` — count matches your input.

Full node-builder script in [content-type-migration.md](content-type-migration.md#node-import-pipeline).

### 6. Build one React component that renders any node

The contract: prop `slug` (or any entity field — see "forgiving matcher" below) → component fetches the matching node and renders. One component handles all instances; the body HTML differs per post.

The full annotated React component is in [content-type-migration.md](content-type-migration.md#react-component-template-annotated). The high points:

- **No JSON:API include**. Includes 400 on most Source Canvas installs (filtering on relationships is brittle). Fetch the bare collection (`/api/node/<bundle>`) and resolve hero/author media in a **second fetch per displayed node** (`/api/media/image/<uuid>`). SWR dedupes both, so total network is one bundle call + one fetch per visible hero.
- **Absolute URLs only**. The Workbench preview iframe is a `srcdoc` document with no usable origin. Read the Source URL from `window.drupalSettings.canvasData.v0.baseUrl` and prefix it to every API call and image URL. Relative URLs route through Canvas's `/canvas/template/.../component/null/...` rewriter, which 303s to nowhere.
- **Render hero as CSS `background-image`, not `<img>`**. Canvas's astro-hydration layer intercepts every `<img>` tag and runs it through a responsive-image processor that requires an `alternateWidths` query param. Plain CDN/file URLs don't carry that param, so the processor swallows the image. `background-image` on a `<div>` bypasses the processor.
- **Body HTML: `dangerouslySetInnerHTML`, not `<FormattedText>`**. Same root cause — `FormattedText` wraps `<img>` tags inside the body. Plain `dangerouslySetInnerHTML` renders the body's HTML directly, with no Canvas processor in the middle. **Wrap that body in `@tailwindcss/typography`'s `prose` classes** (mandatory per Step 3) — the plugin, not hand-rolled utilities, owns paragraph/heading/list/link styling for the rendered HTML.
- **Translate `public://` stream URIs to `/sites/default/files/`**. JSON:API sometimes returns the unresolved Drupal stream URI instead of the public path. The component does this translation before rendering.
- **Forgiving matcher**. The editor may bind `slug` to Title, Path, or NID via Canvas's field-link chip — none of which is what the code expects literally. Try matchers in order: `path.alias` → case-insensitive `title` → numeric `drupal_internal__nid` → fuzzy `endsWith(/slug)`. Whatever the editor picks resolves correctly.
- **Unwrap typed-field envelopes**. List/datetime fields arrive as `{value: "x"}` from JSON:API. Read `.value` before label lookup, otherwise `[OBJECT OBJECT]` shows up in the rendered output.

### 7. Bind the component to a content template (optional but recommended)

So editors don't type slugs manually, add a content template at `content-templates/node.<bundle>.full.json` that auto-fills the component's `slug` prop from the entity's `path.alias`:

```json
{
  "label": "Blog Post — Full content",
  "entityType": "node",
  "bundle": "blog_post",
  "viewMode": "full",
  "elements": {
    "main": {
      "type": "js.blog_post",
      "props": {
        "slug": {
          "sourceType": "entity-field",
          "expression": "ℹ︎␜entity:node:blog_post␝path␞␟alias"
        }
      }
    }
  }
}
```

On Acquia Source, the canvas CLI **cannot push content templates** (the `page_template:administer` endpoint rejects client-credentials OAuth — only user-delegated auth works, which the CLI doesn't use). Two options:

1. Author the template via the Drupal admin UI (Structure → Canvas → Content templates), pasting the JSON from your local file
2. Use a user-delegated `CANVAS_ACCESS_TOKEN` (extracted from the MCP session) instead of client credentials

The local JSON file is still validated by `npx canvas validate` and committed for source-of-truth.

---

## Verification (mandatory before Step 5)

- Every entry in `recon/content-types.json` has a matching content type on Source — verify via `ReadMcpResourceTool drupal://content-types/<bundle>`.
- Every URL in the bundle's scrape inputs has a published node — verify via `list_entities`.
- Every node has a path alias matching its source URL (`/blog/<slug>` etc.).
- Every node's hero_image (and author_photo, if scraped) is a `{target_id: <mid>}` referencing a real media entity — verify a sample via `list_entities(entity_type="media", filters={drupal_internal__mid: <mid>})`.
- The bundle's React component, when mounted with a representative slug, renders title + subtitle + hero + body + author + CTA without console errors. Verify in Workbench.

If a node is missing or a field is empty, fix it now. Nodes have aliases; aliases are stable URLs editors and customers will share. Backfilling later breaks shared links.

---

## See also

- [content-type-migration.md](content-type-migration.md) — full code samples (Playwright scrape script, React component, content template, upload pipeline) and the field-tested failure-mode log
- SKILL.md "Lessons encoded here" — quick-reference list of every gotcha encountered during dynamic-content migration
