#!/usr/bin/env bash
set -euo pipefail

YQ_VERSION="4.53.3"
YQ_SHA256="b4077cab0f9ee5ce8381e602d090daa69a0afb7e57eb9a5b20e9cb416d7f6794"
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz"
INSTALL_DIR="${HOME}/bin"

if command -v yq &>/dev/null; then
    echo "yq is already installed: $(command -v yq)"
    exit 0
fi

read -r -p "yq was not found in PATH. Install yq v${YQ_VERSION} to ${INSTALL_DIR}? [y/N] " answer
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

ARCHIVE="${TMPDIR}/yq.tar.gz"

echo "Downloading yq v${YQ_VERSION}..."
curl -fsSL -o "${ARCHIVE}" "${YQ_URL}"

echo "Validating checksum..."
echo "${YQ_SHA256}  ${ARCHIVE}" | sha256sum --check --status || {
    echo "ERROR: checksum mismatch — download may be corrupted or tampered with." >&2
    exit 1
}

tar -xzf "${ARCHIVE}" -C "${TMPDIR}" ./yq_linux_amd64
install -m 0755 "${TMPDIR}/yq_linux_amd64" "${INSTALL_DIR}/yq"

echo "yq v${YQ_VERSION} installed to ${INSTALL_DIR}/yq"

if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    echo "NOTE: ${INSTALL_DIR} is not in your PATH. Add the following to your shell profile:"
    echo "  export PATH=\"\${HOME}/bin:\${PATH}\""
fi
