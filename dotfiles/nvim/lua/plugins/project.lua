return {
  {
    "ahmedkhalf/project.nvim",
    opts = {
      -- 1. This is the "Magic Switch".
      --    If true, it won't cd. If false, it AUTO cd's.
      manual_mode = false,

      -- 2. Ensure R markers are detected
      -- patterns = { "renv.lock", ".Rprofile", ".git", "Makefile", "package.json" },
    },
  },
}
