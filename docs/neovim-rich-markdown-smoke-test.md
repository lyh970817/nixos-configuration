# Neovim rich Markdown smoke test

Reproducible fixture for the explanation-workspace rendering stack (issue
#11, phase 7): `render-markdown.nvim` owns Markdown structure,
`render-latex.nvim` owns display mathematics, `Snacks.image` owns inline
mathematics plus ordinary images and PDFs. Open this file in the dedicated
Kitty/Neovim workspace and walk top to bottom; every section names what
correct rendering looks like. The document is deliberately long enough to
exercise scrolling and image prefetching. `:ReadMode` (or `<localleader>r`)
toggles the reading mode in which the cursor hops over display equations and
nothing pops open into raw source; explanation-tree buffers open in it by
default.

## Terminal graphics support

Where the equation PNGs and images actually appear depends on the terminal
in front of Neovim (validated 2026-08):

- **Kitty, direct**: full rendering — Kitty graphics protocol works, all
  image placements appear.
- **Herdr pane inside Kitty** (the F7 explanation tab): full rendering,
  provided `[experimental] kitty_graphics = true` is set in
  `dotfiles/herdr/config.toml` (validated 2026-08, herdr 0.8.0, including
  across an SSH hop between the outer Kitty and the herdr client — herdr
  re-emits pane graphics as in-band direct transmissions). Without that
  flag the pane emulator silently drops every graphics sequence: Neovim
  reserves the vertical space but the pixels never arrive, so equations
  and images come out blank.
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

- [ ] open task: verify inline math conceal
- [x] done task: verify display math rasterization
- [ ] open task: verify PDF preview

## 3. Table

| Content | Owner | Notes |
|---|---|---|
| Headings, lists, tables, callouts | `render-markdown.nvim` | anti-conceal on the cursor line |
| Display equations `$$...$$` and `\[...\]` | `render-latex.nvim` | transparent PNG, no background halo |
| Inline equations `$...$` and `\(...\)` | `Snacks.image` | tectonic-rendered image fitted to the line |
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

## 7. Inline mathematics

Inline math must stay in the text flow: the estimator $\hat\theta_n$ is
unbiased when $\mathbb{E}[\hat\theta_n] = \theta$ for all $\theta \in
\Theta$; the variance $\sigma^2 = \mathbb{E}[(X - \mu)^2]$ contrasts with
the sample version $s^2 = \tfrac{1}{n-1}\sum_{i=1}^n (x_i - \bar x)^2$, and
Greek mixes with scripts as in $\alpha_i^{(t+1)}$, $\beta_{j,k}$, and
$\gamma^{\delta^\epsilon}$.

LaTeX bracket delimiters must render exactly like the dollar form: the
share \(S_p\) stays in the text flow, the indicator \(D_{pm}\in\{0,1\}\)
keeps its set braces, and scripts survive as in \(\alpha_i^{(t+1)}\). A
literal `\(x\)` inside inline code must stay raw text.

## 8. Display mathematics

Fractions and roots:

$$
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a},
\qquad
\sqrt[3]{\frac{1 + \sqrt{5}}{2}}
$$

Integrals, sums, and products:

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2},
\qquad
\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6},
\qquad
\prod_{k=1}^{n} \frac{k}{k+1} = \frac{1}{n+1}
$$

Matrices:

$$
\begin{pmatrix} a & b \\ c & d \end{pmatrix}
\begin{pmatrix} x \\ y \end{pmatrix}
=
\begin{bmatrix} ax + by \\ cx + dy \end{bmatrix}
$$

Cases:

$$
f(x) =
\begin{cases}
x \log x & x > 0 \\
0 & x = 0 \\
\text{undefined} & x < 0
\end{cases}
$$

Aligned equations:

$$
\begin{aligned}
\mathbb{E}[(X + Y)^2] &= \mathbb{E}[X^2] + 2\,\mathbb{E}[XY] + \mathbb{E}[Y^2] \\
&= \mathbb{E}[X^2] + 2\,\mathbb{E}[X]\,\mathbb{E}[Y] + \mathbb{E}[Y^2] \\
&= \mathbb{E}[X^2] + \mathbb{E}[Y^2] & \text{when } \mathbb{E}[X] = 0
\end{aligned}
$$

Braces, accents, and operators:

$$
\underbrace{\hat\theta_n - \theta}_{\text{error}}
= \overbrace{\bar{X}_n - \mu}^{\text{sampling}}
+ \tilde\varepsilon_n,
\qquad
\nabla \cdot \vec{F} = \lim_{V \to 0} \frac{1}{|V|} \oint_{\partial V}
\vec{F} \cdot \hat{n}\, dS
$$

Greek letters and nested scripts:

$$
\Gamma(\alpha) = \int_0^\infty t^{\alpha - 1} e^{-t}\,dt,
\qquad
\xi_{i_j}^{k^{\ell_m}} + \Psi_{\omega} \geq \Lambda_{\phi \circ \psi}
$$

Bracket-delimited display form (`\[ ... \]`), which the renderer must also
own:

\[
\operatorname{argmax}_{\theta} \; \log \mathcal{L}(\theta \mid x_{1:n})
= \operatorname{argmax}_{\theta} \sum_{i=1}^n \log f(x_i \mid \theta)
\]

And its single-line variant:

\[ S_p = \frac{\sum_m D_{pm} w_m}{\sum_m w_m} \]

## 9. Malformed LaTeX

The block below is intentionally broken (unbalanced brace, undefined
command). The renderer must degrade gracefully — raw source or an error
placeholder — without crashing, flickering, or corrupting the sections
around it:

$$
\frac{1}{1 + \frac{1}{x}
\quad \notacommand{y} \quad \begin{aligned} a &= b
$$

And a malformed inline one: $e^{i\pi + 1 = 0$ — the paragraph continues and
must still render.

## 10. Images

PNG:

![PNG gradient](assets/smoke-test.png)

JPEG:

![JPEG gradient](assets/smoke-test.jpg)

WebP:

![WebP gradient](assets/smoke-test.webp)

A path containing spaces (both encodings must resolve to the same file):

![spaced path](<assets/smoke test image.png>)

![spaced path, URL-encoded](assets/smoke%20test%20image.png)

## 11. PDF

A PDF link that `Snacks.image` should preview (Ghostscript rasterizes it):

[smoke-test PDF](assets/smoke-test.pdf)

## 12. Scroll ballast

The remaining sections repeat mixed content so that scrolling crosses many
placements: images above must be prefetched or re-rendered without ghost
placements as they leave and re-enter the viewport, and equation-heavy
regions must stay responsive under `Ctrl+D`/`Ctrl+U` paging.

### Ballast A

Bayes' rule with a ratio of integrals:

$$
p(\theta \mid x) =
\frac{f(x \mid \theta)\,\pi(\theta)}
     {\int_\Theta f(x \mid t)\,\pi(t)\,dt}
$$

A paragraph of prose between equations keeps line-height changes visible:
conditional expectation is a projection, and the tower property
$\mathbb{E}[\mathbb{E}[X \mid \mathcal{G}]] = \mathbb{E}[X]$ is its most
used consequence.

### Ballast B

$$
\operatorname{Var}(X) = \mathbb{E}[X^2] - \mathbb{E}[X]^2,
\qquad
\operatorname{Cov}(X, Y) = \mathbb{E}[XY] - \mathbb{E}[X]\,\mathbb{E}[Y]
$$

- list item between equations
- another item with inline math $\rho = \operatorname{Cov}(X,Y)/(\sigma_X \sigma_Y)$

### Ballast C

$$
\begin{aligned}
\|a + b\|^2 &= \|a\|^2 + 2\langle a, b\rangle + \|b\|^2 \\
\|a - b\|^2 &= \|a\|^2 - 2\langle a, b\rangle + \|b\|^2
\end{aligned}
$$

The same PNG again, to test repeated placements of one file:

![PNG gradient repeated](assets/smoke-test.png)

### Ballast D

$$
e^{i\pi} + 1 = 0,
\qquad
\zeta(s) = \sum_{n=1}^\infty n^{-s} = \prod_{p \text{ prime}} \frac{1}{1 - p^{-s}}
$$

Final paragraph: if every section above rendered — including the malformed
block degrading gracefully — the stack passes the static half of the phase-7
smoke test; the interactive half (editing near equations, undo/redo, yank
fidelity, buffer deletion) is exercised in the workspace itself.
