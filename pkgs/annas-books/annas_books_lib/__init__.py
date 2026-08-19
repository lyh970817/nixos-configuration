"""Anna's Archive client, books only.

Papers are deliberately out of scope: Anna's Archive serves the same Sci-Hub
corpus that scansci-oa already reaches for free, while every download here
spends one unit of a per-day membership quota. Books are the case where Anna's
Archive is the only option, so that is all this client does.
"""

__all__ = ["client", "mirrors", "parse", "secrets"]
