# Content-Type Migration Playbook

This is the deep companion to **Step 4c** in SKILL.md. Open it when you're migrating dynamic content (blog posts, articles, case studies, products, team bios, knowledge base entries) from a source site into Drupal content types on Acquia Source with a React component that fetches each node via JSON:API + SWR.

The high-level workflow lives in SKILL.md Step 4c. This file is for the code patterns and the long tail of gotchas — read it before writing the React component or the import pipeline. It assumes you've already decided WHICH bundles to create (with the user) and captured them in `recon/content-types.json`.

---

## Table of contents

1. [Field type cheat sheet](#field-type-cheat-sheet)
2. [Schema verification](#schema-verification)
3. [Scrape pipeline](#scrape-pipeline)
4. [Media upload pipeline](#media-upload-pipeline)
5. [Node import pipeline](#node-import-pipeline)
6. [React component template (annotated)](#react-component-template-annotated)
7. [Content template (auto-binding)](#content-template-auto-binding)
8. [Verification checklist](#verification-checklist)
9. [Failure modes — what we hit and what worked](#failure-modes--what-we-hit-and-what-worked)

---

## Field type cheat sheet

For `mcp__source-mcp__add_field_to_content_type` / `batch_add_fields_to_content_type`:

| Need                       | `field_type`        | Key settings                                                                 |
|----------------------------|---------------------|------------------------------------------------------------------------------|
| Short plain text (≤255)    | `string`            | `storage_settings.max_length: 255` (default)                                 |
| Longer plain text (≤512)   | `string`            | `storage_settings.max_length: 512`                                           |
| Plain-text paragraph       | `string_long`       | (no length cap; not formatted)                                               |
| Rich body HTML             | (built-in `body`)   | Pass `options.create_body_field: true` to `create_content_type`              |
| Date only                  | `datetime`          | `storage_settings.datetime_type: date`                                       |
| Date + time                | `datetime`          | `storage_settings.datetime_type: datetime`                                   |
| Enum / select              | `list_string`       | `storage_settings.allowed_values: { machine_name: "Label", ... }`            |
| Media reference (single)   | `entity_reference`  | `target_type: media`, handler `default:media`, `target_bundles: { image: image }` |
| Multi-value tag/term       | `entity_reference`  | `target_type: taxonomy_term`, `cardinality: -1`                              |
| URL                        | `string` (or `link`)| `link` field type has built-in URL validation if available on this install   |

For prop IDs in `component.yml`: prop ID = `camelCase(title)`. Lint will fail if mismatched. So `Author Photo` → `authorPhoto`, not `author_photo`.

---

## Schema verification

After every `create_content_type` / `batch_add_fields_to_content_type`, read the schema back to confirm everything landed:

```
ReadMcpResourceTool(server="source-mcp", uri="drupal://content-types/<bundle>")
```

Look for each field you intended to add in the `properties` object. The `body` field has `format: enum` listing the allowed text formats (e.g. `filtered_html`, `plain_text`) — use whichever value JSON:API will accept for the install (`filtered_html` is the safest default).

If a field is missing or has the wrong type, re-call `add_field_to_content_type` or `update_field_config` to fix it before importing nodes. Re-imports are cheap; data migrations after the fact are not.

---

## Scrape pipeline

A reusable Node + Playwright pattern that scales to dozens of URLs and writes one JSON per scraped post:

```js
// scripts/scrape-<bundle>.mjs
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';

const OUT = 'recon/blog/raw';
mkdirSync(OUT, { recursive: true });

async function scrape(browser, url) {
  const slug = url.replace(/\/$/, '').split('/').pop();
  const page = await browser.newPage({ viewport: { width: 1280, height: 1200 } });
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForLoadState('load', { timeout: 60000 }).catch(() => {});
    // Force lazy images to load + scroll the page so body imgs paint.
    await page.evaluate(() => {
      document.querySelectorAll('img[loading="lazy"]').forEach((i) => (i.loading = 'eager'));
    });
    for (let y = 0; y < 8; y++) {
      await page.evaluate((s) => window.scrollTo(0, s), y * 800);
      await page.waitForTimeout(150);
    }

    const data = await page.evaluate(() => {
      const abs = (u) => { try { return new URL(u, location.href).href; } catch { return u; } };
      const article = document.querySelector('article') || document.querySelector('main') || document.body;
      const h1 = document.querySelector('h1');
      const title = h1?.textContent?.trim() || document.title.trim();

      // Subtitle: nearest paragraph after H1 of moderate length.
      let subtitle = null;
      if (h1) {
        let scope = h1.parentElement;
        for (let i = 0; i < 4 && scope && !subtitle; i++) {
          for (const el of scope.querySelectorAll('p')) {
            if (el === h1) continue;
            const t = el.textContent.trim();
            if (t.length >= 30 && t.length <= 300 && /[.!?]/.test(t.slice(-3))) {
              if (el.compareDocumentPosition(h1) & Node.DOCUMENT_POSITION_PRECEDING) {
                subtitle = t; break;
              }
            }
          }
          scope = scope.parentElement;
        }
      }

      // Hero: first image inside article with naturalWidth >= 600.
      let hero = null;
      for (const img of article.querySelectorAll('img')) {
        const w = img.naturalWidth || parseInt(img.getAttribute('width') || '0', 10);
        if (w >= 600) { hero = { src: abs(img.currentSrc || img.src), alt: img.alt || '' }; break; }
      }

      // Body: deepest container holding >= 2 <p> and >= 1 <h2>.
      let bodyEl = null, bestScore = 0;
      article.querySelectorAll('div, section, article').forEach((c) => {
        let p = 0, h2 = 0;
        for (const ch of c.children) {
          if (ch.tagName === 'P') p++;
          if (ch.tagName === 'H2') h2++;
        }
        const score = p >= 2 && h2 >= 1 ? p + h2 * 2 : 0;
        if (score > bestScore) { bestScore = score; bodyEl = c; }
      });

      let bodyHtml = '';
      const inlineImages = [];
      if (bodyEl) {
        const clone = bodyEl.cloneNode(true);
        // Strip noise: forms, CTAs, related, share widgets, author block.
        clone.querySelectorAll('form, [class*="form" i], [class*="cta" i], [class*="related" i], [class*="share" i], [class*="newsletter" i], [class*="author" i], button').forEach((el) => el.remove());
        clone.querySelectorAll('img').forEach((img) => {
          const src = abs(img.currentSrc || img.src);
          img.removeAttribute('srcset');
          img.removeAttribute('sizes');
          img.removeAttribute('loading');
          if (src) img.setAttribute('src', src);
          inlineImages.push({ src, alt: img.alt || '' });
        });
        // Strip presentation attrs (preserve only structural HTML).
        clone.querySelectorAll('*').forEach((el) => {
          for (const a of Array.from(el.attributes)) {
            if (a.name.startsWith('data-') || a.name === 'class' || a.name === 'style' || a.name === 'id' || a.name.startsWith('aria-')) {
              el.removeAttribute(a.name);
            }
          }
        });
        bodyHtml = clone.innerHTML.trim();
      }

      // Date: <time> element first, fall back to a "Month DD, YYYY" regex on document text.
      let publishedDate = null;
      const timeEl = document.querySelector('time');
      if (timeEl) publishedDate = timeEl.getAttribute('datetime') || timeEl.textContent.trim();
      if (!publishedDate) {
        const m = document.body.innerText.match(/\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}\b/);
        if (m) publishedDate = m[0];
      }

      // Author: look for an "About the author" block.
      let authorName = null, authorBio = null;
      const headings = Array.from(article.querySelectorAll('h2, h3, h4'));
      const authH = headings.find((h) => /about the author|meet the author/i.test(h.textContent || ''));
      if (authH) {
        // Walk siblings/ancestors for a name line and a bio paragraph.
        let scope = authH.parentElement || document.body;
        for (let i = 0; i < 4 && (!authorName || !authorBio); i++) {
          if (!scope) break;
          for (const el of scope.children) {
            const t = (el.textContent || '').trim();
            if (!authorName && /^[A-Z][a-z'-]+(\s[A-Z][a-z'-]+){1,3}$/.test(t)) authorName = t;
            else if (authorName && !authorBio && el.tagName === 'P' && t.length > 30) { authorBio = t; break; }
          }
          scope = scope.parentElement;
        }
      }

      return { url: location.href, title, subtitle, hero, publishedDate, bodyHtml, inlineImages, author: { name: authorName, bio: authorBio } };
    });

    data.slug = slug;
    writeFileSync(`${OUT}/${slug}.json`, JSON.stringify(data, null, 2));
    return { slug, ok: true };
  } catch (err) {
    return { slug, ok: false, error: err.message };
  } finally {
    await page.close();
  }
}

const urls = process.argv.slice(2);
const browser = await chromium.launch({ headless: true });
const CONC = 3;
let inflight = 0, cursor = 0;
await new Promise((resolve) => {
  function next() {
    if (cursor >= urls.length && inflight === 0) return resolve();
    while (inflight < CONC && cursor < urls.length) {
      const u = urls[cursor++];
      inflight++;
      scrape(browser, u).then((r) => console.log(r.ok ? 'OK' : 'ERR', r.slug, r.error || '')).finally(() => { inflight--; next(); });
    }
  }
  next();
});
await browser.close();
```

Call with the list of URLs as args, or refactor to read from `recon/<bundle>/index.json`.

**The scrape will miss things.** Subtitle and author detection are heuristic — for ~3 posts out of 17 in our workshop, the subtitle came back null or the author was wrong. That's acceptable for the workshop bar; for production, refine the heuristics with site-specific selectors after inspecting the live HTML for the bundle's actual classes.

---

## Media upload pipeline

`media:image` accepts only **jpg/png/gif** on most Source installs — convert webp/avif at download time. For Contentful CDNs, append `?fm=jpg&w=1600&q=85`. For other CDNs, request `Accept: image/jpeg` or convert locally with sharp/ffmpeg.

```js
// scripts/download-and-upload.mjs (skeleton)
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { mkdirSync } from 'node:fs';

const RAW = 'recon/blog/raw';
const HERO_DIR = 'public/media/blog/hero';
mkdirSync(HERO_DIR, { recursive: true });

// Pass 1: download all heroes as jpg.
for (const f of readdirSync(RAW).filter((f) => f.endsWith('.json'))) {
  const data = JSON.parse(readFileSync(`${RAW}/${f}`));
  if (!data.hero?.src) continue;
  let src = data.hero.src;
  try {
    const u = new URL(src);
    if (u.hostname.includes('ctfassets.net')) {
      u.searchParams.set('fm', 'jpg');
      u.searchParams.set('w', '1600');
      u.searchParams.set('q', '85');
      src = u.toString();
    }
  } catch {}
  const res = await fetch(src, { headers: { 'User-Agent': 'Mozilla/5.0' } });
  if (!res.ok) { console.warn(`skip ${data.slug}: ${res.status}`); continue; }
  const buf = Buffer.from(await res.arrayBuffer());
  writeFileSync(`${HERO_DIR}/${data.slug}.jpg`, buf);
}
```

Then in your conversation, batch the `create_media` MCP calls (10–15 in parallel), capture each returned `{mid, upload_url}`, and PUT the bytes in parallel:

```bash
# /tmp/blog-uploads.tsv: mid<TAB>slug<TAB>upload_url per line
while IFS=$'\t' read mid slug url; do
  curl -sS -X PUT "$url" -H "Content-Type: application/octet-stream" --data-binary "@public/media/blog/hero/${slug}.jpg" \
    -o /tmp/up-${mid}.json -w "%{http_code}\n"
done < /tmp/blog-uploads.tsv
```

Save the slug→MID map to `recon/<bundle>/media-target-ids.json` **after every batch** — MCP tokens expire after ~15 min and you must be able to resume without replaying uploads.

For inline body images: same pattern, optional. The Workshop didn't migrate inline body images and accepted that body HTML keeps its original CDN URLs — Drupal's filtered_html format renders external `<img>` tags fine. Migrate them only if the source CDN is going away or you need every asset on Source.

---

## Node import pipeline

Generate a node payload per scraped post. Key rules:

- **Drop null/empty fields** rather than passing `null`. JSON:API rejects empty entity references and complains about empty strings on required-ish fields.
- **Date format** for `datetime_type: date` is `YYYY-MM-DD`. For `datetime`, ISO 8601.
- **Entity references** use `{target_id: <mid>}` for single-value, `[{target_id: <mid>}, ...]` for multi-value.
- **`moderation_state: 'published'`** to publish on create; omit (or set `'draft'`) to keep unpublished.
- **`path: { alias: '/<bundle>/<slug>' }`** to set the URL alias.

```js
// scripts/build-import-payload.mjs
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';

const HERO_MIDS = JSON.parse(readFileSync('recon/blog/media-target-ids.json'));
const CATEGORY = JSON.parse(readFileSync('recon/blog/category-map.json'));
const MONTHS = { January: '01', February: '02', March: '03', April: '04', May: '05', June: '06', July: '07', August: '08', September: '09', October: '10', November: '11', December: '12' };

function parseDate(s) {
  if (!s) return null;
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const m = s.match(/(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})/);
  return m ? `${m[3]}-${MONTHS[m[1]]}-${m[2].padStart(2, '0')}` : null;
}

const nodes = [];
for (const f of readdirSync('recon/blog/raw').filter((f) => f.endsWith('.json'))) {
  const d = JSON.parse(readFileSync(`recon/blog/raw/${f}`));
  const node = {
    title: d.title,
    moderation_state: 'published',
    body: { value: d.bodyHtml, format: 'filtered_html' },
    category: CATEGORY[d.slug],
    path: { alias: `/blog/${d.slug}` },
  };
  if (d.subtitle) node.subtitle = d.subtitle;
  if (d.author?.name) node.author_name = d.author.name;
  if (d.author?.bio) node.author_bio = d.author.bio;
  if (HERO_MIDS[d.slug]) node.hero_image = { target_id: HERO_MIDS[d.slug] };
  const pd = parseDate(d.publishedDate);
  if (pd) node.published_date = pd;
  nodes.push(node);
}
writeFileSync('recon/blog/import-payload.json', JSON.stringify(nodes, null, 2));
console.log(`Built ${nodes.length} node payloads`);
```

Then in your conversation, call `batch_create_nodes` in chunks of ~8 nodes each. The whole-batch payload can grow large (50–150 KB) when body HTML is included — chunks of 8 keep individual tool calls under typical limits while staying efficient.

```
batch_create_nodes(bundle="blog_post", nodes=[<first 8>], options={return_details: false})
batch_create_nodes(bundle="blog_post", nodes=[<next 8>], options={return_details: false})
```

If a batch returns `failed > 0`, the response details the failing nodes' violations. Fix and retry that batch.

---

## React component template (annotated)

This is the contract: prop `slug` → component fetches the matching node and renders. One component, all posts. Comments call out the gotchas inline.

```jsx
// src/components/blog_post/index.jsx
import { useMemo } from 'react';
import { cn } from 'drupal-canvas';
import useSWR from 'swr';

// The Workbench preview is a srcdoc iframe — window.location.origin is
// "null"/"about://" and useless. Drupal exposes the real Source origin on
// drupalSettings.canvasData.v0.baseUrl. Read it once at runtime.
function sourceOrigin() {
  if (typeof window === 'undefined') return '';
  const candidates = [
    window.drupalSettings?.canvasData?.v0?.baseUrl,
    window.drupalSettings?.canvas?.siteUrl,
    window.drupalSettings?.path?.baseUrl,
  ];
  for (const c of candidates) {
    if (c && /^https?:\/\//.test(c)) return c.replace(/\/$/, '');
  }
  return window.location.origin || '';
}

// Canvas uses /api/ (not /jsonapi/) as the prefix; canvasData.v0.jsonapiSettings.apiPrefix is "api".
function jsonApiPrefix() {
  if (typeof window === 'undefined') return '/api';
  const cfg = window.drupalSettings?.canvasData?.v0?.jsonapiSettings || null;
  const prefix = cfg?.apiPrefix || cfg?.basePath || 'api';
  return `${sourceOrigin()}/${String(prefix).replace(/^\/+|\/+$/g, '')}`;
}

// Fetch ALL nodes — no ?include=. Every nested include path returns 400 on this
// Canvas install, and filter[path.alias] returns 503. The collection is small
// (≤100s of nodes) and SWR dedupes across instances.
async function fetchAllPosts() {
  const url = `${jsonApiPrefix()}/node/blog_post`;
  const res = await fetch(url, {
    credentials: 'same-origin',
    headers: { Accept: 'application/vnd.api+json' },
  });
  if (!res.ok) throw new Error(`JSON:API ${res.status} for ${url}`);
  const json = await res.json();
  // No include → relationships are { data: { type, id } } only. Keep the UUID
  // for a second per-media fetch.
  return json.data.map((r) => ({
    ...r.attributes,
    hero_image_uuid: r.relationships?.hero_image?.data?.id || null,
    author_photo_uuid: r.relationships?.author_photo?.data?.id || null,
  }));
}

// Second hop: get a media entity's file URL. Tries include=media_image first
// (Canvas custom field name), then field_media_image (Drupal default), then
// thumbnail, then no include (some serializers flatten the URL onto attributes).
async function fetchMediaFileUrl(uuid) {
  if (!uuid) return null;
  for (const q of ['include=media_image', 'include=field_media_image', 'include=thumbnail', '']) {
    const url = `${jsonApiPrefix()}/media/image/${uuid}${q ? `?${q}` : ''}`;
    const res = await fetch(url, {
      credentials: 'same-origin',
      headers: { Accept: 'application/vnd.api+json' },
    });
    if (!res.ok) continue;
    const json = await res.json();
    const file = (json.included || []).find((r) => r.type === 'file--file');
    const fileUrl = file?.attributes?.uri?.url || file?.attributes?.url || file?.attributes?.uri?.value;
    if (fileUrl) return fileUrl;
    const attrs = json.data?.attributes || {};
    const inline = attrs.media_image?.url || attrs.media_image?.src_with_alternate_widths || attrs.field_media_image?.url || attrs.thumbnail?.url || null;
    if (inline) return inline;
  }
  return null;
}

function resolveMediaUrl(url) {
  if (!url) return null;
  // public:// stream wrappers — translate to the public-files path.
  if (url.startsWith('public://')) url = `/sites/default/files/${url.slice(9)}`;
  else if (url.startsWith('private://')) url = `/system/files/${url.slice(10)}`;
  if (/^https?:\/\//.test(url)) return url;
  return `${sourceOrigin()}${url.startsWith('/') ? '' : '/'}${url}`;
}

const CATEGORY_LABEL = {
  travel_hospitality: 'Travel & Hospitality',
  workplace_wellness: 'Workplace Wellness',
  // ...
};

const BlogPost = ({
  slug = '',
  ctaHeading = 'Bring Peloton to your exercisers',
  ctaDescription = '',
  ctaLabel = 'Contact Sales',
  ctaHref = '/contact-sales',
}) => {
  // Accept either bare slug ("foo") or full path ("/blog/foo"). The content
  // template binds slug to path.alias which is the full path.
  const rawSlug = (slug || '').trim();
  const trimmedSlug = rawSlug.startsWith('/blog/') ? rawSlug.slice(6).replace(/\/+$/, '') : rawSlug.replace(/^\/+|\/+$/g, '');

  const { data: posts, error, isLoading } = useSWR('blog_post-all', fetchAllPosts);

  // Forgiving matcher: try path.alias → title → NID → fuzzy suffix.
  const post = useMemo(() => {
    if (!Array.isArray(posts) || !trimmedSlug) return null;
    const aliasOf = (n) => {
      if (typeof n?.path === 'string') return n.path;
      if (n?.path?.alias) return n.path.alias;
      if (Array.isArray(n?.path) && n.path[0]?.alias) return n.path[0].alias;
      return null;
    };
    const wanted = `/blog/${trimmedSlug}`;
    let found = posts.find((n) => aliasOf(n) === wanted);
    if (found) return found;
    found = posts.find((n) => (n?.title || '').toLowerCase() === trimmedSlug.toLowerCase() || (n?.title || '').toLowerCase() === rawSlug.toLowerCase());
    if (found) return found;
    if (/^\d+$/.test(trimmedSlug)) {
      const nid = Number(trimmedSlug);
      found = posts.find((n) => n?.drupal_internal__nid === nid);
      if (found) return found;
    }
    return posts.find((n) => aliasOf(n)?.endsWith(`/${trimmedSlug}`)) || null;
  }, [posts, rawSlug, trimmedSlug]);

  // Hero + author photo: second SWR fetch per UUID, deduped across instances.
  const { data: heroFileUrl } = useSWR(
    post?.hero_image_uuid ? ['media-file', post.hero_image_uuid] : null,
    ([, id]) => fetchMediaFileUrl(id),
  );
  const { data: authorPhotoFileUrl } = useSWR(
    post?.author_photo_uuid ? ['media-file', post.author_photo_uuid] : null,
    ([, id]) => fetchMediaFileUrl(id),
  );

  const heroSrc = resolveMediaUrl(heroFileUrl);
  const authorPhotoSrc = resolveMediaUrl(authorPhotoFileUrl);

  // Unwrap list_string envelope before label lookup.
  const categoryKey = typeof post?.category === 'string' ? post.category : post?.category?.value || null;
  const category = categoryKey ? CATEGORY_LABEL[categoryKey] || categoryKey : null;

  // Body comes through as { value, format } — render .value via dangerouslySetInnerHTML.
  // FormattedText would wrap inline <img> tags in Canvas's responsive-image
  // processor, which fails on plain CDN/file URLs ("Responsive image generation
  // failed"). dangerouslySetInnerHTML bypasses the wrapper.
  const bodyHtml = post?.body?.processed || post?.body?.value || '';

  if (!trimmedSlug) return <section className="px-6 py-16 text-center text-ink-subtle">Pass a <code>slug</code> prop.</section>;
  if (error) return <section className="px-6 py-16 text-center text-ink-muted">Couldn't load this story.</section>;
  if (isLoading) return <article className="animate-pulse">...</article>;
  if (!post) return <section className="px-6 py-16 text-center text-ink-muted">No post found at /blog/{trimmedSlug}.</section>;

  return (
    <article className="bg-surface text-ink">
      <header className="mx-auto max-w-3xl px-6 pt-16 pb-10">
        {category && <p className="text-xs font-semibold uppercase tracking-widest text-brand-primary">{category}</p>}
        <h1 className="mt-4 text-4xl font-bold leading-tight sm:text-5xl">{post.title}</h1>
        {post.subtitle && <p className="mt-5 text-xl leading-relaxed text-ink-muted">{post.subtitle}</p>}
        {post.author_name && <p className="mt-8 text-sm text-ink-subtle">By <span className="font-semibold text-ink">{post.author_name}</span></p>}
      </header>

      {/* Hero as background-image, NOT <img>. Canvas's astro hydration
          intercepts <img> via next-image-standalone and rejects URLs that
          lack ?alternateWidths=. Background-image on a <div> is invisible
          to that processor. */}
      {heroSrc && (
        <div className="mx-auto max-w-5xl px-6">
          <div
            role="img"
            aria-label={post.title}
            className="aspect-[16/9] w-full overflow-hidden rounded-lg bg-surface-subtle bg-cover bg-center"
            style={{ backgroundImage: `url("${heroSrc}")` }}
          />
        </div>
      )}

      <div className="mx-auto max-w-3xl px-6 py-12 sm:py-16">
        <div
          className={cn('prose prose-lg max-w-none', '[&_h2]:mt-12', '[&_p]:my-5')}
          dangerouslySetInnerHTML={{ __html: bodyHtml }}
        />
      </div>

      {/* Bottom CTA — props, no fetch. */}
      <section className="bg-dark text-dark-text">
        <div className="mx-auto max-w-3xl px-6 py-16 text-center">
          <h2 className="text-3xl font-bold">{ctaHeading}</h2>
          {ctaDescription && <p className="mt-4 text-lg">{ctaDescription}</p>}
          <a href={ctaHref} className="mt-8 inline-flex items-center rounded-full bg-cta-bg-inverted px-8 py-3 font-semibold text-cta-text-inverted">{ctaLabel}</a>
        </div>
      </section>
    </article>
  );
};

export default BlogPost;
```

The matching `component.yml`:

```yaml
name: Blog Post
machineName: blog_post
status: true
required:
  - slug
props:
  properties:
    slug:
      title: Slug
      type: string
      description: Bind to the node's Title (or Path) field via the field-link chip.
      examples:
        - summer-hospitality-wellness-trends
    ctaHeading:
      title: Cta Heading
      type: string
      examples: [Bring Peloton to your exercisers]
    ctaDescription:
      title: Cta Description
      type: string
    ctaLabel:
      title: Cta Label
      type: string
      examples: [Contact Sales]
    ctaHref:
      title: Cta Href
      type: string
      examples: [/contact-sales]
slots: {}
```

---

## Content template (auto-binding)

So editors don't type slugs manually, add `content-templates/node.<bundle>.full.json` that auto-fills `slug` from the entity's `path.alias` (the component already handles the `/blog/` prefix):

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
        },
        "ctaHeading": "Bring Peloton to your exercisers",
        "ctaDescription": "Discover how Peloton takes your commercial fitness center to the next level.",
        "ctaLabel": "Contact Sales",
        "ctaHref": "/contact-sales"
      }
    }
  }
}
```

Validates locally with `npx canvas validate`. **Push via CLI is blocked on Acquia Source** — the `page_template:administer` route rejects client-credentials OAuth. Author it via the Drupal admin UI (Structure → Canvas → Content templates) or use a user-delegated `CANVAS_ACCESS_TOKEN`. Either way, keep the JSON file as source of truth.

---

## Verification checklist

Before declaring Step 4c done:

- [ ] Every entry in `recon/content-types.json` exists on Source as a content type. Verify via `ReadMcpResourceTool drupal://content-types/<bundle>`.
- [ ] Every URL in each bundle's scrape set has a published node. Verify via `list_entities(entity_type="node", bundle="<bundle>")` count.
- [ ] Every node has a path alias matching its source URL.
- [ ] Every node's hero_image (and author_photo if scraped) is `{target_id: <mid>}` referencing a real media entity.
- [ ] The bundle's React component, mounted with a representative slug, renders title + subtitle + hero + body + author + CTA in Workbench without console errors.
- [ ] The component's only network calls are `GET /api/node/<bundle>` (200) and `GET /api/media/image/<uuid>?include=…` (200 per visible hero/author photo). Zero 400/503/HTML responses.
- [ ] Console is clean: no "Responsive image generation failed", no "Unexpected token '<'", no `/canvas/template/.../component/null/...` 303s.
- [ ] The content template JSON file exists, validates clean, and (if deployed) renders the component automatically when an editor views a node.

---

## Failure modes — what we hit and what worked

A field log of every bug from this session, with the exact symptom and the fix. If you see one of these symptoms on a future run, jump straight to the fix.

### Content type creation

- **`Workflow "editorial" does not exist`**: every Source install names its workflow differently. Read the actual machine name from `/admin/config/workflow/workflows/manage/<id>` in the admin UI or ask the user.
- **`Workflow "<correct_name>" does not exist` despite confirming it in the admin UI**: the MCP is authenticated to a different Source than the one the user is viewing. `list_entities` returning `canonicalUrl` on a different host is the tell. Re-auth via `mcp__source-mcp__authenticate` and complete the OAuth flow against the right host.

### Media upload

- **`File extension "webp" is not allowed for media type "image"`**: the schema's `supported types` list is install-aspirational; the media:image bundle is often restricted to jpg/png/gif. Convert to jpg before upload (Contentful: `?fm=jpg`; otherwise sharp/ffmpeg).
- **`Unsupported image type "image/svg+xml"`**: SVG isn't supported on media:image. Convert to PNG.
- **MCP token expired mid-upload**: tokens expire after ~15 min. Save the slug→MID map after every batch so you can resume. Re-auth and continue from the last saved slug.

### JSON:API fetch

- **`/api/node/<bundle>?include=hero_image.field_media_image` → 400**: the nested include path is wrong for this install. Try `media_image` (Canvas custom) instead of `field_media_image`. If both fail (common), drop the include and fetch media separately.
- **`/api/node/<bundle>?include=hero_image,author_photo` → 400**: combining two relationships fails if one of them has no value on any node. Pick one or split into two requests.
- **`/api/node/<bundle>?filter[path.alias]=...` → 503**: filtering on path alias forces a slow JOIN. Fetch the bare collection and match client-side.
- **`getResourceByPath('/blog/<slug>')` → HTML response, "Unexpected token '<'"**: the JsonApiClient wrapper hits an endpoint that doesn't exist on this install (or returns the login page). Use plain `fetch()` for direct API access and explicit error handling.
- **`?sort=-published_date` → 400**: JSON:API can reject sort params on datetime fields. Sort client-side after fetching.

### Image rendering

- **"Responsive image generation failed. To fix this: 1. Provide a custom `loader` function, or 2. Ensure your image `src` includes an `alternateWidths` query parameter"**: Canvas's `next-image-standalone` wraps every `<img>` tag and requires the param. Two paths: (1) render as CSS `background-image` on a `<div>` (the processor only targets `<img>`), or (2) provide a custom loader if you genuinely need responsive images.
- **`Request URL: …/canvas/template/<entity>/<bundle>/<view_mode>/<id>/component/null/sites/default/files/...`**: Canvas's template-asset rewriter intercepted a relative URL because the component-instance ID was unknown (`null`). The 303 redirect goes nowhere useful. Fix: always use absolute Source URLs (prepend `drupalSettings.canvasData.v0.baseUrl`).
- **Hero shows as a gray placeholder**: the `heroSrc` is non-null but the URL fails to load. Most often the URL is a `public://` stream URI that needs translation, or the URL is relative and the iframe origin is `about:srcdoc`. Translate stream wrappers and force absolute URLs.
- **`<svg> attribute width: Expected length, "auto"`** errors: these come from the Drupal Gin admin theme SVG icons, not your component. Ignore.

### Body rendering

- **`[OBJECT OBJECT]` shows in the eyebrow / metadata**: a typed field (list_string, datetime) arrived as `{value: "x"}` and was concatenated as a string. Unwrap to `.value` before label lookup or formatting.
- **Body images warn "Responsive image generation failed" 9× per page**: `<FormattedText>` is wrapping inline `<img>` tags. Switch to `dangerouslySetInnerHTML` for the body.

### Content templates

- **`canvas push --include-content-templates true` → `invalid_scope` or "The used authentication method is not allowed on this route"**: client-credentials OAuth is blocked on the `page_template:administer` route. Use the admin UI or a user-delegated `CANVAS_ACCESS_TOKEN`.
- **Editor binds slug to Title and the page shows "No blog post found at /blog/How to Level Up..."**: the matcher only checked `path.alias`. Add fallbacks for title (case-insensitive), NID, and fuzzy suffix so any field binding resolves.
- **The field-link chip on an image prop only offers "Alternative text", "Title", "Media"**: stored leaf properties, not the computed file URL. Use `$ref: json-schema-definitions://canvas.module/image` for image props; Canvas resolves the media reference to a full image schema. If the chip dropdown still doesn't include the field, fall back to the SWR fetch by slug (already covered).

### Environment

- **`canvas push` fails with auth error after the workflow works fine in MCP**: `.env`'s `CANVAS_SITE_URL` may be stale. Update it to match the host that returns 2xx in the MCP calls (check `list_entities` canonical URLs for the right host).
- **Component changes don't take effect in Workbench after `canvas push`**: hard-refresh (⌘⇧R / Ctrl+Shift+R). Canvas's component bundle is aggressively cached. If still stale, check Network → Disable cache → reload.
