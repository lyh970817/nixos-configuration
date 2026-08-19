{
  lib,
  writeShellApplication,
  coreutils,
  scansci-pdf,
  dataDir,
}:

# Confined front end for scansci-pdf: pins the data directory, allows only the
# `get` subcommand, and restricts the strategy to the two free/shadow modes.
# `fetch`, `login`, `federated-login`, `publisher-batch` and `import-cookies`
# drive the institutional ladder or launch browsers, so they stay unreachable --
# scansci-pdf itself is never put on PATH.
writeShellApplication {
  name = "scansci-oa";
  runtimeInputs = [ coreutils ];
  text = ''
    export SCANSCI_PDF_DATA_DIR=${lib.escapeShellArg dataDir}
    mkdir -p "$SCANSCI_PDF_DATA_DIR"

    usage() {
      cat <<'USAGE'
    Usage: scansci-oa <DOI|arXiv-ID> [-o DIR] [--strategy grey_only|oa_first] [--no-bibtex]

    Downloads one paper from free and shadow sources. No institutional access,
    no browser automation, no Tor.
    USAGE
    }

    strategy=grey_only
    args=()
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
          args+=(--output "''${2:-}")
          shift 2
          ;;
        --output=*)
          args+=(--output "''${1#*=}")
          shift
          ;;
        --no-bibtex)
          args+=(--no-bibtex)
          shift
          ;;
        -h | --help)
          usage
          exit 0
          ;;
        --)
          shift
          args+=("$@")
          break
          ;;
        -*)
          echo "scansci-oa: unknown option $1" >&2
          usage >&2
          exit 2
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done

    case "$strategy" in
      grey_only | oa_first) ;;
      *)
        echo "scansci-oa: --strategy must be grey_only or oa_first" >&2
        exit 2
        ;;
    esac

    if [ ''${#args[@]} -eq 0 ]; then
      usage >&2
      exit 2
    fi

    # Only ever `get`. Every positional argument lands after it, so a subcommand
    # name passed here is read as an identifier, not as a command.
    exec ${lib.getExe scansci-pdf} get --strategy "$strategy" "''${args[@]}"
  '';
}
