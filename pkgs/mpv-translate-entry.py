#!/usr/bin/env python3
"""Start the unchanged upstream CLI with the CPU runtimes initialized in order.

The executable name selects the command and the caption profile:
`mpv-translate[-<profile>][-direct]` and `mpv-translate[-<profile>]-models`.
The default profile keeps upstream's config lookup; a named profile reads
only `~/.config/mpv-translate/<profile>.toml`.
"""

import functools
import pathlib
import sys

# Loading Torch after CTranslate2 inference crashes in OpenBLAS GEMM on both
# hosts. Initialize Torch first; changing OMP/OPENBLAS thread counts was insufficient.
import torch

from mpv_translate import config, nllb

# Upstream hard-codes NLLB-200 3.3B: about 13 GB of float32 weights on these
# CPU-only hosts. The distilled 600M model uses the same tokenizer and codes.
nllb.MODEL_NAME = "facebook/nllb-200-distilled-600M"

PROFILE_DIR = pathlib.Path("~/.config/mpv-translate").expanduser()


def translator_model(cfg: config.Config) -> str:
    match cfg.translate.translator:
        case "nllb":
            return nllb.MODEL_NAME
        case "opus":
            return f"Helsinki-NLP/opus-mt-{cfg.translate.language}-{cfg.translate.target_lang}"
    raise ValueError(f"no model to cache for translator {cfg.translate.translator!r}")


def download_models(profiles: list[str]) -> None:
    """Cache every profile's models: upstream loads Whisper with local_files_only."""
    from faster_whisper.utils import download_model
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    for profile in profiles:
        cfg = config.get_config() if profile == "" else load_profile(profile)
        print(f"[{profile or 'default'}] Downloading Whisper {cfg.model.model}…", flush=True)
        download_model(cfg.model.model)
        name = translator_model(cfg)
        print(f"[{profile or 'default'}] Downloading {name}…", flush=True)
        AutoTokenizer.from_pretrained(name)
        AutoModelForSeq2SeqLM.from_pretrained(name)
    print("Caption models cached. Start playback with: mpv-translate /path/to/video.mkv")


def load_profile(profile: str) -> config.Config:
    return config.load_config_paths(PROFILE_DIR / f"{profile}.toml")


name = pathlib.Path(sys.argv[0]).name.removeprefix("mpv-translate")
if name == "-models":
    download_models([""] + sorted(p.stem for p in PROFILE_DIR.glob("*.toml") if p.name != "config.toml"))
    sys.exit()

command = "direct" if name.endswith("-direct") else "cli"
profile = name.removesuffix("-direct").removeprefix("-")
if profile:
    # Replace before importing the CLI: upstream modules bind get_config at import.
    config.get_config = functools.cache(lambda: load_profile(profile))

from mpv_translate.cli import cli, direct  # noqa: E402

{"cli": cli, "direct": direct}[command]()
