# Neovim rich Markdown smoke test

Reproducible fixture for the explanation-workspace rendering stack (issue
#11, phase 7): `render-markdown.nvim` owns Markdown structure, `Snacks.image`
owns images and PDFs; mathematics stays raw TeX. Open this file in the
dedicated Kitty/Neovim workspace and walk top to bottom; every section names
what correct rendering looks like. The document is deliberately long enough to
exercise scrolling and image prefetching. `:ReadMode` (or `<localleader>r`)
toggles the reading mode in which nothing pops open into raw source;
explanation-tree buffers open in it by default.

## Terminal graphics support

Where the images actually appear depends on the terminal
in front of Neovim (validated 2026-08):

- **Kitty, direct**: full rendering — Kitty graphics protocol works, all
  image placements appear.
- **Herdr pane inside Kitty** (the F7 explanation tab): full rendering,
  provided `[experimental] kitty_graphics = true` is set in
  `dotfiles/herdr/config.toml` (validated 2026-08, herdr 0.8.0, including
  across an SSH hop between the outer Kitty and the herdr client — herdr
  re-emits pane graphics as in-band direct transmissions). Without that
  flag the pane emulator silently drops every graphics sequence: Neovim
  reserves the vertical space but the pixels never arrive, so images come
  out blank.
- **Foot**: raw fallback — no graphics protocol; text-level rendering only.

## 1. Headings and inline styles

Second-level heading above; below, inline styles inside a paragraph: **bold**,
*italic*, ***bold italic***, `inline code`, ~~strikethrough~~, a [link to the
issue](https://github.com/lyh970817/nixos-configuration/issues/11), and a
footnote-like reference[^note].

[^note]: Footnote content renders at the bottom of the document.

### Third level

#### Fourth level

##### Fifth level, rarely styled distinctly — must still not break layout

## 2. Lists and checkboxes

Unordered, with nesting:

- explanation trees live under `~/.local/share/explanations/`
  - `explanation.md` is the root document
  - `children/` holds conceptual detours
    - grandchildren are allowed but rare
- the lock file is `.explain.lock`; the kernel flock is authoritative

Ordered, interrupted by a nested unordered list:

1. insert a question with `<localleader>q`
2. save and submit with `<localleader>s`
   - buffers become read-only while the update runs
   - `:checktime` reloads after the writer exits
3. the focused buffer switches to the answer

Checkboxes:

- [ ] open task: verify image placement after undo
- [x] done task: verify table wrapping
- [ ] open task: verify PDF preview

## 3. Table

| Content | Owner | Notes |
|---|---|---|
| Headings, lists, tables, callouts | `render-markdown.nvim` | anti-conceal on the cursor line |
| Images, PDFs | `Snacks.image` | Kitty graphics protocol |
| A deliberately long cell to force horizontal layout decisions in narrow windows | everyone | wraps or scrolls, never overlaps |

## 4. Quotes and callouts

> A plain block quote: the durable artifact is the Markdown tree, not a
> long-running agent process.

> [!NOTE]
> A note callout rendered by `render-markdown.nvim`.

> [!WARNING]
> A warning callout; the icon and title must survive the question blocks
> below using the same syntax.

## 5. Question blocks

An open question (the parser counts exactly this one):

<!-- explain-question id="q-3f2a8c1e-5b7d-4e9f-a1c2-d3e4f5a6b7c8" status="open" -->
> [!QUESTION]
> I understand the independence claim, but where do the cross terms disappear
> algebraically?
<!-- /explain-question -->

A resolved question (retained, no longer counted):

<!-- explain-question id="q-9d8c7b6a-5f4e-3d2c-b1a0-918273645546" status="resolved" -->
> [!QUESTION]
> Why is the estimator unbiased? — answered in
> [children/law-of-total-expectation.md](children/law-of-total-expectation.md).
<!-- /explain-question -->

## 6. Code blocks

```python
def open_questions(text: str) -> list[Question]:
    return [q for q in parse_questions(text) if q.status == "open"]
```

```sh
explainctl submit "$HOME/.local/share/explanations/demo/explanation.md"
```

```text
plain fenced block: no language, no highlighting, still boxed
```

## 7. Images

PNG:

![PNG gradient](assets/smoke-test.png)

JPEG:

![JPEG gradient](assets/smoke-test.jpg)

WebP:

![WebP gradient](assets/smoke-test.webp)

A path containing spaces (both encodings must resolve to the same file):

![spaced path](<assets/smoke test image.png>)

![spaced path, URL-encoded](assets/smoke%20test%20image.png)

## 8. PDF

A PDF link that `Snacks.image` should preview (Ghostscript rasterizes it):

[smoke-test PDF](assets/smoke-test.pdf)

## 9. Scroll ballast

The remaining sections repeat mixed content so that scrolling crosses many
placements: images above must be prefetched or re-rendered without ghost
placements as they leave and re-enter the viewport, and the buffer must stay
responsive under `Ctrl+D`/`Ctrl+U` paging.

### Ballast A

A paragraph of prose keeps line-height changes visible: conditional
expectation is a projection, and the tower property is its most used
consequence.

- list item between paragraphs
- another item, with `inline code`

### Ballast B

> A quote between images, to check that placements do not bleed into
> neighbouring blocks.

The same PNG again, to test repeated placements of one file:

![PNG gradient repeated](assets/smoke-test.png)

### Ballast C

| Column | Value |
| ------ | ----- |
| first  | 1     |
| second | 2     |

Final paragraph: if every section above rendered, the stack passes the static
half of the phase-7 smoke test; the interactive half (editing near images,
undo/redo, yank fidelity, buffer deletion) is exercised in the workspace
itself.
