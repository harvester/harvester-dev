#!/usr/bin/env bash
set -euo pipefail

TASK_VERSION="3.49.1"
TASK_SHA256="4e7d24f1bf38218aec8f244eb7ba671f898830f9f87b3c9b30ff1c09e3135576"
TASK_URL="https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz"
INSTALL_DIR="${HOME}/bin"

if command -v task &>/dev/null; then
    echo "task is already installed: $(command -v task)"
    exit 0
fi

read -r -p "task was not found in PATH. Install task v${TASK_VERSION} to ${INSTALL_DIR}? [y/N] " answer
case "${answer}" in
    [yY][eE][sS]|[yY]) ;;
    *)
        echo "Aborted."
        exit 1
        ;;
esac

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
