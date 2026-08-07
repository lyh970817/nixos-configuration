require("git"):setup { order = 0 }
require("smart-enter"):setup { open_multi = true }
require("full-border"):setup()
require("starship"):setup()
require("session"):setup {
    sync_yanked = true,
}

require("folder-rules"):setup()
