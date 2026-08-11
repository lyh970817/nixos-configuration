#!/usr/bin/env bash

set -euo pipefail

case ",${WLR_BACKENDS:-}," in
  *,headless,*) headless_backend=1 ;;
  *) headless_backend=0 ;;
esac

if [[ ${AQ_HEADLESS_ONLY:-} == 1 || $headless_backend == 1 ]]; then
  exit 0
fi

exec "$@"
