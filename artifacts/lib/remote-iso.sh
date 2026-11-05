# Shared helpers for select-*-remote-iso.sh. Source this file; don't run it.
#
# The caller sets CONFIG_FILE and defines usage(),
# then calls:
#   remote_iso_parse_args "$@"   # sets VERSION, NAME, RELEASE_SERVER, ...
#   remote_url FILE              # URL for a release file (proxied if asked)
#   remote_iso_check REQUIRED... -- OPTIONAL...

remote_iso_options_help() {
  cat <<EOF
Options:
  --release-server URL  Release server base URL
                        (default: .harvester_release_url in config.yaml)
  --proxy               Fetch through the artifact server proxy
                        (http -> /proxy/, https -> /proxy_ssl/)
  --proxy-insecure      Like --proxy, but https -> /proxy_ssl_insecure/
                        (accept self-signed certificates)
  -h, --help            Show this help

VERSION defaults to master.
EOF
}

# Parse [--release-server URL] [--proxy | --proxy-insecure] [VERSION] and
# set RELEASE_SERVER, PROXY_MODE ("", "secure" or "insecure"), VERSION,
# RELEASE_PREFIX, NAME, BASE_URL and, with a proxy, ARTIFACT_SERVER_URL.
remote_iso_parse_args() {
  RELEASE_SERVER=""
  PROXY_MODE=""
  VERSION=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --release-server)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
          echo "Error: --release-server requires a URL" >&2
          exit 1
        fi
        RELEASE_SERVER="$2"
        shift 2
        ;;
      --release-server=*)
        RELEASE_SERVER="${1#*=}"
        shift
        ;;
      --proxy)
        PROXY_MODE="secure"
        shift
        ;;
      --proxy-insecure)
        PROXY_MODE="insecure"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "Error: unknown option '$1'" >&2
        usage >&2
        exit 1
        ;;
      *)
        if [ -n "$VERSION" ]; then
          echo "Error: unexpected argument '$1'" >&2
          usage >&2
          exit 1
        fi
        VERSION="$1"
        shift
        ;;
    esac
  done

  VERSION="${VERSION:-master}"
  if [ -z "$RELEASE_SERVER" ]; then
    RELEASE_SERVER=$(yq -e '.harvester_release_url' "$CONFIG_FILE")
  fi
  RELEASE_SERVER="${RELEASE_SERVER%/}"
  RELEASE_PREFIX=$(yq -e '.harvester_release_prefix // "harvester"' "$CONFIG_FILE")

  case "$RELEASE_SERVER" in
    http://*|https://*) ;;
    *)
      echo "Error: release server must start with http:// or https://: $RELEASE_SERVER" >&2
      exit 1
      ;;
  esac

  if [ -n "$PROXY_MODE" ]; then
    if [ "$(yq '.artifacts.proxy_enabled == true' "$CONFIG_FILE")" != "true" ]; then
      echo "Error: --proxy needs artifacts.proxy_enabled: true in config.yaml" >&2
      echo "       (then run 'task artifacts-up' to restart the server)" >&2
      exit 1
    fi
    ARTIFACT_SERVER_URL=$(yq -e '.artifact_server_url' "$CONFIG_FILE")
    ARTIFACT_SERVER_URL="${ARTIFACT_SERVER_URL%/}"
  fi

  NAME="${RELEASE_PREFIX}-${VERSION}"
  BASE_URL="$RELEASE_SERVER/$VERSION"
}

# Print the URL clients should use for a file in the release directory:
# the remote URL itself, or the artifact server proxy path for it.
remote_url() {
  local url="$BASE_URL/$1"
  if [ -z "$PROXY_MODE" ]; then
    echo "$url"
    return
  fi

  local location
  case "$url" in
    http://*) location="proxy" ;;
    https://*)
      if [ "$PROXY_MODE" = "insecure" ]; then
        location="proxy_ssl_insecure"
      else
        location="proxy_ssl"
      fi
      ;;
  esac
  echo "$ARTIFACT_SERVER_URL/$location/${url#*://}"
}

# HEAD a URL. Prints a reason and returns 1 if it isn't usable.
# Through the proxy, redirects are not followed: the proxy passes them to
# the client unchanged, which would send VMs to the remote host directly.
remote_check_url() {
  local url="$1" out code redirect
  if [ -n "$PROXY_MODE" ]; then
    out=$(curl -sI -o /dev/null --max-time 30 \
      -w '%{http_code} %{redirect_url}' "$url" || true)
  else
    out=$(curl -sIL -o /dev/null --max-time 30 \
      -w '%{http_code} %{redirect_url}' "$url" || true)
  fi
  code="${out%% *}"
  redirect="${out#* }"

  case "$code" in
    200) return 0 ;;
    301|302|303|307|308)
      echo "redirects to $redirect; pass that location with --release-server"
      ;;
    000) echo "connection failed" ;;
    *) echo "HTTP $code" ;;
  esac
  return 1
}

# Print the selection, HEAD every URL and exit 1 if a required one fails.
# Usage: remote_iso_check REQUIRED_URL... -- OPTIONAL_URL...
remote_iso_check() {
  echo "Release server: $RELEASE_SERVER"
  echo "Version: $VERSION"
  if [ "$PROXY_MODE" = "insecure" ]; then
    echo "Proxy: $ARTIFACT_SERVER_URL (TLS certificates not verified)"
  elif [ -n "$PROXY_MODE" ]; then
    echo "Proxy: $ARTIFACT_SERVER_URL"
  fi
  echo ""
  echo "Checking remote files..."

  local url reason failed=0 optional=false
  for url in "$@"; do
    if [ "$url" = "--" ]; then
      optional=true
      continue
    fi
    if reason=$(remote_check_url "$url"); then
      echo "  ok:    $url"
    elif [ "$optional" = true ]; then
      echo "  skip:  $url ($reason)"
    else
      echo "  error: $url ($reason)"
      failed=1
    fi
  done

  if [ "$failed" -ne 0 ]; then
    echo ""
    echo "Error: required files are missing; config.yaml not changed." >&2
    exit 1
  fi
  echo ""
}
