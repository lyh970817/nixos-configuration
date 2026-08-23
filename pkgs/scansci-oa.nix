{
  lib,
  writeShellApplication,
  coreutils,
  scansci-pdf,
  dataDir,
}:

# Confined front end for scansci-pdf: allows only the `get` subcommand, pins the
# data directory, and never lets a user-supplied value reach the underlying CLI
# as an option. `fetch`, `login`, `federated-login`, `publisher-batch` and
# `import-cookies` drive the institutional ladder or launch browsers, so they
# stay unreachable -- scansci-pdf itself is never put on PATH.
#
# Two passes, grey first. Upstream's `download()` submits every source of the
# selected pool to one thread pool, so the fastest responder wins and an
# in-process ordering like `scihub_first` is cosmetic. Real precedence therefore
# has to be two separate invocations: `grey_only` (SciBban/LibGen/Sci-Hub, which
# upstream deliberately does not fall back from) for the version of record, then
# `legal_only` (Unpaywall, OpenAlex, DOAJ, EuropePMC, CORE, PMC, ...) for
# whatever preprint exists.
#
# Each pass gets its own SCANSCI_PDF_DATA_DIR *and* its own download directory
# under it. The download directory matters as much as the data directory:
# `.doi_index.json`, the DOI->file map that short-circuits a download, is
# written into the output directory, not into the data directory. Sharing one
# output directory would let an open-access preprint fetched by the fallback
# satisfy every later grey pass for that DOI. Separate directories make that
# impossible without deleting anything, and a pass still re-races the network
# after its own earlier miss because only successes are ever indexed.
writeShellApplication {
  name = "scansci-oa";
  runtimeInputs = [ coreutils ];
  text = ''
    root=${lib.escapeShellArg dataDir}
    prog=${lib.getExe scansci-pdf}

    usage() {
      cat <<'USAGE'
    Usage: scansci-oa <DOI|arXiv-ID> [-o DIR] [--strategy STRATEGY] [--no-bibtex]

    Downloads one paper from free and shadow sources. No institutional access,
    no browser automation, no Tor.

      grey_first  (default) race the shadow libraries first; on a miss fall back
                  to open access, which usually yields a preprint or accepted
                  manuscript rather than the published version of record
      grey_only   shadow libraries only
      legal_only  open access only

    The pass that served the file is reported, so you can tell a version of
    record from a preprint.
    USAGE
    }

    strategy=grey_first
    output=.
    extra=()
    ids=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --strategy)
          strategy="''${2:-}"
          shift 2
          ;;
        --strategy=*)
          strategy="''${1#--strategy=}"
          shift
          ;;
        -o | --output)
          output="''${2:-}"
          shift 2
          ;;
        --output=*)
          output="''${1#*=}"
          shift
          ;;
        --no-bibtex)
          extra+=(--no-bibtex)
          shift
          ;;
        -h | --help)
          usage
          exit 0
          ;;
        --)
          shift
          ids+=("$@")
          break
          ;;
        -*)
          echo "scansci-oa: unknown option $1" >&2
          usage >&2
          exit 2
          ;;
        *)
          ids+=("$1")
          shift
          ;;
      esac
    done

    case "$strategy" in
      grey_first | grey_only | legal_only) ;;
      *)
        echo "scansci-oa: --strategy must be grey_first, grey_only or legal_only" >&2
        exit 2
        ;;
    esac

    if [ ''${#ids[@]} -ne 1 ]; then
      usage >&2
      exit 2
    fi
    id=''${ids[0]}

    if [ -z "$output" ]; then
      echo "scansci-oa: --output needs a directory" >&2
      exit 2
    fi
    mkdir -p "$output"

    served_file=""

    # Run one pass. $1 names both the pass and its directory under $root, whose
    # config.json pins download_strategy (home/programs/scansci-oa.nix). Only
    # ever `get`, and the identifier is the sole positional, so a subcommand name
    # passed here is read as an identifier and not as a command.
    run_pass() {
      local pass=$1 data papers out line
      data=$root/$pass
      papers=$data/papers
      mkdir -p "$papers"

      # `get` prints "  FAILED:" on a miss but never raises typer.Exit, so it
      # exits 0 either way; success has to be read off the "  OK: " marker.
      # Progress logging goes to stderr and stays live.
      out=$(SCANSCI_PDF_DATA_DIR="$data" "$prog" get "$id" --output "$papers" ''${extra[@]+"''${extra[@]}"}) || true
      printf '%s\n' "$out"

      served_file=""
      while IFS= read -r line; do
        case "$line" in
          "  OK: "*)
            served_file=''${line#"  OK: "}
            break
            ;;
        esac
      done <<<"$out"

      [ -n "$served_file" ] && [ -f "$served_file" ]
    }

    served=""
    case "$strategy" in
      grey_first)
        if run_pass grey; then
          served=grey
        else
          echo "scansci-oa: grey pass found nothing, falling back to open access" >&2
          if run_pass oa; then
            served=oa
          fi
        fi
        ;;
      grey_only)
        if run_pass grey; then
          served=grey
        fi
        ;;
      legal_only)
        if run_pass oa; then
          served=oa
        fi
        ;;
    esac

    if [ -z "$served" ]; then
      echo "scansci-oa: no PDF for $id ($strategy)" >&2
      exit 1
    fi

    # The pass keeps its copy: that is the per-pass cache which keeps a repeat
    # run off the network, and nothing here ever deletes.
    dest=$output/$(basename "$served_file")
    cp -f -- "$served_file" "$dest"

    case "$served" in
      grey)
        echo "scansci-oa: served by the GREY pass (shadow libraries) -- published version of record"
        ;;
      oa)
        echo "scansci-oa: served by the OPEN-ACCESS pass -- likely a preprint or accepted manuscript, not the version of record"
        ;;
    esac
    echo "scansci-oa: $dest"
  '';
}
