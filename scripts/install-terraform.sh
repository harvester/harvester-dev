#!/usr/bin/env bash
set -euo pipefail

TERRAFORM_VERSION="1.15.7"
TERRAFORM_SHA256="73bbb8f5188ad75d4fb853fd100ae4d7e146ef7af7db18776109642fdb7759d2"
TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
INSTALL_DIR="${HOME}/bin"

if command -v terraform &>/dev/null; then
    echo "terraform is already installed: $(command -v terraform)"
    exit 0
fi

read -r -p "terraform was not found in PATH. Install terraform v${TERRAFORM_VERSION} to ${INSTALL_DIR}? [y/N] " answer
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

ARCHIVE="${TMPDIR}/terraform.zip"

echo "Downloading terraform v${TERRAFORM_VERSION}..."
curl -fsSL -o "${ARCHIVE}" "${TERRAFORM_URL}"

echo "Validating checksum..."
echo "${TERRAFORM_SHA256}  ${ARCHIVE}" | sha256sum --check --status || {
    echo "ERROR: checksum mismatch — download may be corrupted or tampered with." >&2
    exit 1
}

unzip -q "${ARCHIVE}" -d "${TMPDIR}"
install -m 0755 "${TMPDIR}/terraform" "${INSTALL_DIR}/terraform"

echo "terraform v${TERRAFORM_VERSION} installed to ${INSTALL_DIR}/terraform"

if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    echo "NOTE: ${INSTALL_DIR} is not in your PATH. Add the following to your shell profile:"
    echo "  export PATH=\"\${HOME}/bin:\${PATH}\""
fi
