import json
import os
from pathlib import Path
import sys
import tempfile

import tomlkit


def save(path, text):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        output.write(text)
    os.replace(output.name, path)


profile = Path(sys.argv[1])
profile.mkdir(mode=0o700, parents=True, exist_ok=True)
config_path = profile / "config.toml"
config = tomlkit.parse(config_path.read_text()) if config_path.exists() else tomlkit.document()
if len(sys.argv) == 3:
    canonical = tomlkit.parse(Path(sys.argv[2]).read_text())
    for key in (
        "model", "model_reasoning_effort", "include_collaboration_mode_instructions",
        "developer_instructions",
    ):
        config[key] = canonical[key]
    config.setdefault("features", {})["multi_agent_v2"] = canonical["features"]["multi_agent_v2"]

config.pop("sandbox_mode", None)
config.pop("sandbox_workspace_write", None)
config["default_permissions"] = ":danger-full-access"
config["approval_policy"] = "never"
config["approvals_reviewer"] = "user"
save(config_path, tomlkit.dumps(config))

state_path = profile / ".codex-global-state.json"
state = json.loads(state_path.read_text()) if state_path.exists() else {}
atoms = state.setdefault("electron-persisted-atom-state", {})
atoms.setdefault("composer-permission-mode-visibility", {})["full-access"] = True
atoms.setdefault("agent-mode-by-host-id", {})["local"] = "full-access"
save(state_path, json.dumps(state))
