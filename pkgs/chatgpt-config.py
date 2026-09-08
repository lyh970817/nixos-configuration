import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

import tomlkit


def save(path, text):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        output.write(text)
    os.replace(output.name, path)


parser = argparse.ArgumentParser()
parser.add_argument("profile", type=Path)
parser.add_argument("canonical", type=Path, nargs="?")
parser.add_argument("--resources", type=Path, required=True)
args = parser.parse_args()

profile = args.profile
profile.mkdir(mode=0o700, parents=True, exist_ok=True)
config_path = profile / "config.toml"
config = tomlkit.parse(config_path.read_text()) if config_path.exists() else tomlkit.document()
if args.canonical is not None:
    canonical = tomlkit.parse(args.canonical.read_text())
    for key in (
        "model", "model_reasoning_effort", "include_collaboration_mode_instructions",
        "developer_instructions",
    ):
        config[key] = canonical[key]
    config.setdefault("features", {})["multi_agent_v2"] = canonical["features"]["multi_agent_v2"]

# Old local marketplace snapshots survive application upgrades. Match the
# browser client to the service shipped by the running application, without
# changing either plugin code or the runtime's trust policy.
marketplace = args.resources / "plugins/openai-bundled"
config.setdefault("marketplaces", {})["openai-bundled"] = {
    "source_type": "local",
    "source": str(marketplace),
}
for name in ("browser", "chrome"):
    cache = profile / "plugins/cache/openai-bundled" / name
    enabled = config.get("plugins", {}).get(f"{name}@openai-bundled", {}).get("enabled", False)
    if not enabled and not cache.exists():
        continue
    source = marketplace / "plugins" / name
    version = json.loads((source / ".codex-plugin/plugin.json").read_text())["version"]
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / version
    if not target.exists():
        with tempfile.TemporaryDirectory(prefix=".install-", dir=cache) as staging:
            staged = Path(staging) / version
            shutil.copytree(source, staged)
            # Nix store directories are read-only; cache directories must be
            # movable and removable by the application that owns them.
            for directory, _, _ in os.walk(staged):
                path = Path(directory)
                path.chmod(path.stat().st_mode | 0o700)
            staged.rename(target)
    with tempfile.TemporaryDirectory(prefix=".latest-", dir=cache) as staging:
        link = Path(staging) / "latest"
        link.symlink_to(version)
        os.replace(link, cache / "latest")

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
