[
  {
    name = "DESKTOP · LAUNCH";
    bindings = [
      {
        description = "Home session over SSH";
        key = "Super + Enter";
      }
      {
        description = "Local Herdr session";
        key = "Super + Shift + Enter";
      }
      {
        description = "Application launcher";
        key = "Super + R";
      }
      {
        description = "Window switcher";
        key = "Super + Shift + R";
      }
      {
        description = "Brave";
        key = "Super + W";
      }
      {
        description = "Yazi in Foot";
        key = "Super + E";
      }
      {
        description = "Thunar";
        key = "Super + Shift + E";
      }
      {
        description = "Date and time";
        key = "Super + D";
      }
    ];
  }
  {
    name = "DESKTOP · WINDOWS";
    bindings = [
      {
        description = "Focus left / down / up / right";
        key = "Super + h / j / k / l";
      }
      {
        description = "Move window left / down / up / right";
        key = "Super + Shift + h / j / k / l";
      }
      {
        description = "Next / previous window";
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
        description = "Resize with arrows";
        key = "Super + Arrow keys";
      }
      {
        description = "Drag / resize with mouse";
        key = "Super + left / right drag";
      }
      {
        description = "Send window behind others";
        key = "Alt + Shift + b";
      }
    ];
  }
  {
    name = "DESKTOP · WORKSPACES";
    bindings = [
      {
        description = "Switch to workspace 1–10";
        key = "Super + 1…0";
      }
      {
        description = "Move window to workspace 1–10";
        key = "Super + Shift + 1…0";
      }
      {
        description = "Next / previous existing workspace";
        key = "Super + wheel down / up";
      }
      {
        description = "Move window to workspace 10";
        key = "Super + m";
      }
    ];
  }
  {
    name = "DESKTOP · DISPLAY";
    bindings = [
      {
        description = "Toggle dark / light theme";
        key = "Super + Shift + t";
      }
      {
        description = "Toggle night colour temperature";
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
        description = "Restore laptop display after lid event";
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
        description = "Toggle long-form dictation";
        key = "Ctrl + Shift + l";
      }
      {
        description = "Toggle dictation profile";
        key = "Ctrl + Shift + p";
      }
      {
        description = "Cancel long-form dictation";
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
        description = "Toggle microphone mute";
        key = "Fn + F4";
      }
      {
        description = "Brightness down / up";
        key = "Fn + F6 / F7";
      }
      {
        description = "Toggle Mihomo proxy";
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
        description = "Cycle monitor scale";
        key = "Fn + Space";
      }
      {
        description = "Volume mute / down / up";
        key = "Fn + Esc / 3 / 4";
      }
      {
        description = "Microphone volume down / up";
        key = "Ctrl + Shift + d / u";
      }
    ];
  }
  {
    name = "HERDR · PANES";
    bindings = [
      {
        description = "Focus left / down / up / right";
        key = "Alt + h / j / k / l";
      }
      {
        description = "Swap left / down / up / right";
        key = "Alt + Shift + h / j / k / l";
      }
      {
        description = "Split pane side by side";
        key = "Alt + Enter";
      }
      {
        description = "Toggle pane zoom";
        key = "Alt + f";
      }
      {
        description = "Close pane and any empty tab / workspace";
        key = "Alt + q";
      }
      {
        description = "Enter keyboard copy mode";
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
        description = "Focus or create persistent tab slot 1–9";
        key = "Alt + 1…9";
      }
    ];
  }
  {
    name = "HERDR · WORKSPACES";
    bindings = [
      {
        description = "Open session navigator";
        key = "Alt + g";
      }
      {
        description = "Open workspace picker";
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
        description = "Toggle agent sidebar";
        key = "Alt + e";
      }
      {
        description = "Previous / next agent";
        key = "Alt + Up / Down";
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
        description = "Cycle audio track";
        key = "#";
      }
    ];
  }
  {
    name = "MPV · SUBTITLES";
    bindings = [
      {
        description = "Next / previous subtitle track";
        key = "j / Shift + j";
      }
      {
        description = "Subtitle 100 ms earlier / later";
        key = "z / Shift + z";
      }
    ];
  }
  {
    name = "SHELL · KEYS";
    bindings = [
      {
        description = "Accept next suggested word";
        key = "Alt + f";
      }
      {
        description = "Accept full suggestion";
        key = "Ctrl + f";
      }
      {
        description = "Open Yazi and return in chosen directory";
        key = "Ctrl + o";
      }
      {
        description = "Fuzzy command history";
        key = "Ctrl + r";
      }
      {
        description = "Zeno completion";
        key = "Tab";
      }
      {
        description = "Directory history back / forward";
        key = "Ctrl + Left / Right";
      }
      {
        description = "Directory history up / down";
        key = "Ctrl + Up / Down";
      }
    ];
  }
  {
    name = "SHELL · CUSTOM ALIASES";
    bindings = [
      {
        description = "Ask Whai a natural-language question";
        key = ",";
      }
      {
        description = "Rebuild NixOS from /etc/nixos";
        key = "rebuild";
      }
      {
        description = "Codex · unrestricted";
        key = "cdy";
      }
      {
        description = "Codex orchestrator · unrestricted";
        key = "cdo";
      }
      {
        description = "Claude · unrestricted";
        key = "cly";
      }
      {
        description = "Opus 5 orchestrator · orchestrator-opus.md";
        key = "clo";
      }
      {
        description = "Fable 5 orchestrator · orchestrator-fable.md";
        key = "clfo";
      }
      {
        description = "Claude Matt Pocock profile";
        key = "claude-matt";
      }
      {
        description = "Claude local GPT-5.6 gateway";
        key = "clg";
      }
      {
        description = "Claude Matt profile · unrestricted";
        key = "clty";
      }
      {
        description = "Claude GPT-5.6 gateway · unrestricted";
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
