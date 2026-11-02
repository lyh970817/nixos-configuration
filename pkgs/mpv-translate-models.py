#!/usr/bin/env python3
"""Download the configured caption models into the user's Hugging Face cache."""

from faster_whisper.utils import download_model
from mpv_translate.config import get_config
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer


config = get_config()
print(f"Downloading Whisper {config.model.model}…", flush=True)
download_model(config.model.model)

model_name = (
    f"Helsinki-NLP/opus-mt-{config.translate.language}-{config.translate.target_lang}"
)
print(f"Downloading {model_name}…", flush=True)
AutoTokenizer.from_pretrained(model_name)
AutoModelForSeq2SeqLM.from_pretrained(model_name)
print("Caption models cached. Start playback with: mpv-translate /path/to/video.mkv")
