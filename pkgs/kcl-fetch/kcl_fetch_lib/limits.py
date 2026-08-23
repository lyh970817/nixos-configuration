"""Rate and budget limits, and the one-way valve that keeps them tight.

Every field has a *direction of safety*. A limit may only ever be moved in the
safe direction by configuration; an override that would loosen anything is a
hard error, not a warning and not a clamp. Silently clamping would let a
mistaken config look accepted, and the failure mode we are guarding against --
a publisher block landing on KCL's whole IP range, or an EZproxy `UsageLimit`
trip that needs a library administrator to clear -- is not one anybody notices
in time to correct.
"""

from __future__ import annotations

from dataclasses import dataclass, fields
from typing import Any, Mapping

#: Field name -> direction that makes the configuration *stricter*.
#: "up" means a larger value is safer (waits, window lengths); "down" means a
#: smaller value is safer (caps, thresholds).
_SAFE_DIRECTION = {
    "global_min_interval": "up",
    "host_cooldown": "up",
    "short_window_seconds": "up",
    "short_window_max": "down",
    "long_window_seconds": "up",
    "long_window_max": "down",
    "enumeration_window_seconds": "up",
    "enumeration_issue_threshold": "down",
    "enumeration_sequential_threshold": "down",
    "min_pdf_bytes": "down",
}


class LimitsConfigError(ValueError):
    """A configuration tried to loosen a limit, or named an unknown one."""


@dataclass(frozen=True)
class Limits:
    #: Springer's own published figure for non-API downloading is one request
    #: per second; treat it as the ceiling for every publisher, not the floor.
    global_min_interval: float = 1.0

    #: On top of the global spacing, no single publisher host is touched again
    #: within this many seconds.
    host_cooldown: float = 5.0

    #: Rolling budgets. EZproxy's stock `UsageLimit` abuse trigger is on the
    #: order of 500 transfers or 100MB in 180 minutes; 25/3h sits an order of
    #: magnitude below it, which is where a human reader actually lives.
    short_window_seconds: float = 3 * 3600.0
    short_window_max: int = 25
    long_window_seconds: float = 24 * 3600.0
    long_window_max: int = 100

    #: Enumeration: systematically walking an issue or a DOI range is the exact
    #: pattern named in KCL's and the publishers' abuse policies, and it is what
    #: gets an institution cut off rather than throttled.
    enumeration_window_seconds: float = 24 * 3600.0
    enumeration_issue_threshold: int = 3
    enumeration_sequential_threshold: int = 3

    #: A "PDF" below this is a cover page, an error page, or a preview stub.
    min_pdf_bytes: int = 20 * 1024

    def tighten(self, overrides: Mapping[str, Any] | None) -> "Limits":
        """Return a copy with `overrides` applied, refusing any loosening."""
        if not overrides:
            return self
        known = {f.name for f in fields(self)}
        updated: dict[str, Any] = {}
        for name, raw in overrides.items():
            if name not in known:
                raise LimitsConfigError(
                    f"unknown limit {name!r}; known limits: {', '.join(sorted(known))}"
                )
            current = getattr(self, name)
            value = type(current)(raw)
            direction = _SAFE_DIRECTION[name]
            if direction == "up" and value < current:
                raise LimitsConfigError(
                    f"{name} may only be raised (stricter): {value} < {current}"
                )
            if direction == "down" and value > current:
                raise LimitsConfigError(
                    f"{name} may only be lowered (stricter): {value} > {current}"
                )
            updated[name] = value
        return Limits(**{**{f.name: getattr(self, f.name) for f in fields(self)}, **updated})


#: The shipped limits. `Limits.tighten` is the only way to derive from these,
#: so no configuration path can produce a Limits that is looser than this.
DEFAULTS = Limits()
