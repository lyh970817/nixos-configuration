-- Markdown rendering stack (issue #11, phase 5). Ownership is exclusive:
-- render-latex.nvim owns all mathematics; Snacks.image owns ordinary
-- images/PDFs (plugins/snacks.lua disables its math path).
return {
  {
    "techwizrd/render-latex.nvim",
    ft = { "markdown" },
    -- Early release: pin the Lua code and the prebuilt Rust worker to the
    -- same tested tag (v0.1.0-rc4, latest release as of 2026-08). The worker
    -- downloads on first load; validate with :RenderLatex doctor and
    -- :checkhealth render_latex on each host.
    version = "v0.1.0-rc4",
    opts = {
      -- Default render_modes = { "n", "i" } keeps equations rendered while
      -- editing (the live-preview behaviour; rc4 has no `live_preview` key).
      install = { version = "v0.1.0-rc4" },
      render = {
        -- Match buffer text colour/size; display math becomes transparent
        -- PNGs, inline math stays a conceal fallback (no image flicker).
        preset = "match_text",
        inline = "conceal",
        inline_symbols = true,
      },
    },
  },
}
