[
  {
    name = "DESKTOP · LAUNCH";
    bindings = [
      {
        description = "Home terminal";
        key = "Super + Enter";
      }
      {
        description = "Local Herdr";
        key = "Super + Shift + Enter";
      }
      {
        description = "Launch applications";
        key = "Super + R";
      }
      {
        description = "Switch windows";
        key = "Super + Shift + R";
      }
      {
        description = "Brave";
        key = "Super + W";
      }
      {
        description = "Yazi in Kitty";
        key = "Super + E";
      }
      {
        description = "Thunar";
        key = "Super + Shift + E";
      }
      {
        description = "Date & time";
        key = "Super + D";
      }
    ];
  }
  {
    name = "DESKTOP · WINDOWS";
    bindings = [
      {
        description = "Focus by direction";
        key = "Super + h / j / k / l";
      }
      {
        description = "Move by direction";
        key = "Super + Shift + h / j / k / l";
      }
      {
        description = "Cycle windows";
        key = "Super + Tab / Super + Shift + Tab";
      }
      {
        description = "Close / force close";
        key = "Super + q / Super + Shift + q";
      }
      {
        description = "Toggle floating";
        key = "Super + s";
      }
      {
        description = "Toggle fullscreen";
        key = "Super + f";
      }
      {
        description = "Toggle pseudotile";
        key = "Super + p";
      }
      {
        description = "Toggle split direction";
        key = "Super + v";
      }
      {
        description = "Resize window";
        key = "Super + Arrow keys";
      }
      {
        description = "Move / resize with mouse";
        key = "Super + left / right drag";
      }
      {
        description = "Send window to back";
        key = "Alt + Shift + b";
      }
    ];
  }
  {
    name = "DESKTOP · WORKSPACES";
    bindings = [
      {
        description = "Switch workspace 1–10";
        key = "Super + 1…0";
      }
      {
        description = "Move to workspace 1–10";
        key = "Super + Shift + 1…0";
      }
      {
        description = "Cycle existing workspaces";
        key = "Super + wheel down / up";
      }
      {
        description = "Minimize to workspace 10";
        key = "Super + m";
      }
    ];
  }
  {
    name = "DESKTOP · DISPLAY";
    bindings = [
      {
        description = "Switch dark / light theme";
        key = "Super + Shift + t";
      }
      {
        description = "Toggle night colour";
        key = "Super + n";
      }
      {
        description = "Full screenshot";
        key = "Print";
      }
      {
        description = "Region screenshot";
        key = "Super + Shift + s";
      }
      {
        description = "Turn display on";
        key = "Fn + F12";
      }
    ];
  }
  {
    name = "VOICE";
    bindings = [
      {
        description = "Toggle short dictation";
        key = "Super + o";
      }
      {
        description = "Revert dictation to raw transcript";
        key = "Super + Shift + o";
      }
      {
        description = "Toggle long dictation";
        key = "Ctrl + Shift + l";
      }
      {
        description = "Switch dictation profile";
        key = "Ctrl + Shift + p";
      }
      {
        description = "Cancel long dictation";
        key = "Super + Escape";
      }
    ];
  }
  {
    name = "LAPTOP · HARDWARE";
    bindings = [
      {
        description = "Cycle power profile";
        key = "Fn + F2";
      }
      {
        description = "Toggle mic mute";
        key = "Fn + F4";
      }
      {
        description = "Brightness down / up";
        key = "Fn + F6 / F7";
      }
      {
        description = "Toggle proxy";
        key = "Fn + F8";
      }
      {
        description = "Toggle touchpad";
        key = "Fn + F9";
      }
      {
        description = "Cycle keyboard backlight";
        key = "Fn + Z";
      }
      {
        description = "Cycle display scale";
        key = "Fn + Space";
      }
      {
        description = "Volume mute / down / up";
        key = "Fn + Esc / 3 / 4";
      }
      {
        description = "Mic volume down / up";
        key = "Ctrl + Shift + d / u";
      }
    ];
  }
  {
    name = "CODEX · TUI";
    bindings = [
      {
        description = "Open transcript";
        key = "Ctrl + o";
      }
      {
        description = "Copy selected response";
        key = "F12";
      }
    ];
  }
  {
    name = "HERDR · PANES";
    bindings = [
      {
        description = "Focus by direction";
        key = "Alt + h / j / k / l";
      }
      {
        description = "Swap by direction";
        key = "Alt + Shift + h / j / k / l";
      }
      {
        description = "Split pane to the right";
        key = "Alt + Enter";
      }
      {
        description = "Toggle zoom";
        key = "Alt + f";
      }
      {
        description = "Close pane";
        key = "Alt + q";
      }
      {
        description = "Copy mode";
        key = "Alt + v";
      }
    ];
  }
  {
    name = "HERDR · TABS";
    bindings = [
      {
        description = "Previous / next tab";
        key = "Alt + Shift + Tab / Alt + Tab";
      }
      {
        description = "Select tab by ordinal";
        key = "Alt + 1…9";
      }
    ];
  }
  {
    name = "HERDR · WORKSPACES";
    bindings = [
      {
        description = "Session navigator";
        key = "Alt + g";
      }
      {
        description = "Workspace picker";
        key = "Alt + w";
      }
      {
        description = "Previous / next workspace";
        key = "Alt + Left / Right";
      }
      {
        description = "Create workspace";
        key = "Alt + n";
      }
    ];
  }
  {
    name = "HERDR · AGENTS";
    bindings = [
      {
        description = "Toggle sidebar";
        key = "Alt + e";
      }
      {
        description = "Previous / next agent";
        key = "Alt + Up / Down";
      }
      {
        description = "Resume Claude / Codex · new tab";
        key = "F1 / F2";
      }
      {
        description = "Resume Claude / Codex · split right";
        key = "F3 / F4";
      }
      {
        description = "Resume Claude / Codex · split below";
        key = "F5 / F6";
      }
      {
        description = "Start fresh in the same destination";
        key = "Shift + F1…F6";
      }
    ];
  }
  {
    name = "EXPLAIN";
    bindings = [
      {
        description = "Fork focused Claude session (Herdr)";
        key = "F7";
      }
      {
        description = "Insert anchored question";
        key = "\\q";
      }
      {
        description = "Save and submit open questions";
        key = "\\s";
      }
      {
        description = "Toggle READ / EDIT mode";
        key = "\\r";
      }
      {
        description = "Root, metadata, lock state";
        key = ":ExplainStatus";
      }
      {
        description = "Open root document";
        key = ":ExplainOpenRoot";
      }
      {
        description = "Create from origin session";
        key = ":ExplainNew";
      }
    ];
  }
  {
    name = "YAZI · NAVIGATION";
    bindings = [
      {
        description = "Previous / next file";
        key = "k / j";
      }
      {
        description = "Parent / enter or open";
        key = "h / l";
      }
      {
        description = "Previous / next directory";
        key = "Shift + h / Shift + l";
      }
      {
        description = "Move 5 files up / down";
        key = "Ctrl + u / Ctrl + d";
      }
      {
        description = "Top / bottom";
        key = "g g / Shift + g";
      }
      {
        description = "Filter files";
        key = "f";
      }
      {
        description = "Find file";
        key = "/";
      }
      {
        description = "Next / previous find match";
        key = "n / Shift + n";
      }
    ];
  }
  {
    name = "YAZI · FILES";
    bindings = [
      {
        description = "Toggle / visual selection";
        key = "Space / v";
      }
      {
        description = "Open / choose opener";
        key = "o / Shift + o";
      }
      {
        description = "Yank copy / cut";
        key = "y / x";
      }
      {
        description = "Yank copy following symlinks";
        key = "Shift + y";
      }
      {
        description = "Paste / overwrite";
        key = "p / Shift + p";
      }
      {
        description = "Create / rename";
        key = "a / r";
      }
      {
        description = "Trash / permanently delete";
        key = "d / Shift + d";
      }
      {
        description = "Toggle hidden files";
        key = ".";
      }
    ];
  }
  {
    name = "YAZI · TOOLS";
    bindings = [
      {
        description = "Spot hovered file";
        key = "s";
      }
      {
        description = "Extract archives / create zip";
        key = "Shift + e / Shift + z";
      }
      {
        description = "Git root / changed files";
        key = "g r / g c";
      }
      {
        description = "Open interactive shell";
        key = "$";
      }
      {
        description = "Change permissions";
        key = "c m";
      }
      {
        description = "Mount manager";
        key = "Shift + m";
      }
      {
        description = "Zoom preview in / out";
        key = "+ / -";
      }
      {
        description = "Maximize parent / files / preview";
        key = "Ctrl + 1 / 2 / 3";
      }
    ];
  }
  {
    name = "MPV · AUDIO";
    bindings = [
      {
        description = "Volume down / up";
        key = "9 / 0";
      }
      {
        description = "Next audio track";
        key = "#";
      }
    ];
  }
  {
    name = "MPV · SUBTITLES";
    bindings = [
      {
        description = "Next / previous subtitles";
        key = "j / Shift + j";
      }
      {
        description = "Subtitles 100 ms earlier / later";
        key = "z / Shift + z";
      }
    ];
  }
  {
    name = "SHELL · KEYS";
    bindings = [
      {
        description = "Accept suggested word";
        key = "Alt + f";
      }
      {
        description = "Accept full suggestion";
        key = "Ctrl + f";
      }
      {
        description = "Yazi; keep chosen directory";
        key = "Ctrl + o";
      }
      {
        description = "Search command history";
        key = "Ctrl + r";
      }
      {
        description = "Fuzzy completion";
        key = "Tab";
      }
      {
        description = "Previous / next visited directory";
        key = "Ctrl + Left / Right";
      }
      {
        description = "Parent / first child directory";
        key = "Ctrl + Up / Down";
      }
    ];
  }
  {
    name = "SHELL · CUSTOM ALIASES";
    bindings = [
      {
        description = "Ask Whai";
        key = ",";
      }
      {
        description = "Rebuild NixOS";
        key = "rebuild";
      }
      {
        description = "Codex (yolo)";
        key = "cdy";
      }
      {
        description = "Codex orchestrator (yolo)";
        key = "cdo";
      }
      {
        description = "Claude (yolo)";
        key = "cly";
      }
      {
        description = "Opus 5 orchestrator (yolo)";
        key = "clo";
      }
      {
        description = "Fable 5 orchestrator (yolo)";
        key = "clfo";
      }
      {
        description = "Claude · Matt Pocock";
        key = "claude-matt";
      }
      {
        description = "Claude · local GPT-5.6";
        key = "clg";
      }
      {
        description = "Claude · Matt Pocock (yolo)";
        key = "clty";
      }
      {
        description = "Claude · local GPT-5.6 (yolo)";
        key = "clgy";
      }
      {
        description = "Git status";
        key = "gs";
      }
      {
        description = "Git push";
        key = "gp";
      }
      {
        description = "Git force push";
        key = "gpf";
      }
    ];
  }
]
