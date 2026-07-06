#!/usr/bin/env bash
set -euo pipefail

TASK_VERSION="3.52.0"
TASK_SHA256="02c679ffae53dca791804847d78b31731615894e292948397c971c87ac9e95bd"
TASK_URL="https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz"
INSTALL_DIR="${HOME}/bin"

FORCE=false
for arg in "$@"; do
    case "${arg}" in
        --force) FORCE=true ;;
        *) echo "Unknown option: ${arg}" >&2; exit 1 ;;
    esac
done

if command -v task &>/dev/null; then
    if [[ "${FORCE}" == false ]]; then
        echo "task is already installed: $(command -v task)"
        exit 0
    fi
elif [[ "${FORCE}" == false ]]; then
    read -r -p "task was not found in PATH. Install task v${TASK_VERSION} to ${INSTALL_DIR}? [y/N] " answer
    case "${answer}" in
        [yY][eE][sS]|[yY]) ;;
        *)
            echo "Aborted."
            exit 1
            ;;
    esac
fi

mkdir -p "${INSTALL_DIR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

ARCHIVE="${TMPDIR}/task.tar.gz"

echo "Downloading task v${TASK_VERSION}..."
curl -fsSL -o "${ARCHIVE}" "${TASK_URL}"

echo "Validating checksum..."
echo "${TASK_SHA256}  ${ARCHIVE}" | sha256sum --check --status || {
    echo "ERROR: checksum mismatch — download may be corrupted or tampered with." >&2
    exit 1
}

tar -xzf "${ARCHIVE}" -C "${TMPDIR}" task
install -m 0755 "${TMPDIR}/task" "${INSTALL_DIR}/task"

echo "task v${TASK_VERSION} installed to ${INSTALL_DIR}/task"

if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    echo "NOTE: ${INSTALL_DIR} is not in your PATH. Add the following to your shell profile:"
    echo "  export PATH=\"\${HOME}/bin:\${PATH}\""
fi
