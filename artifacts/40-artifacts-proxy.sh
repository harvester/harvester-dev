#!/bin/sh
# Enable the proxy locations when ARTIFACTS_PROXY_ENABLED=true. Run by the
# nginx image entrypoint from /docker-entrypoint.d/.
set -eu

mkdir -p /etc/nginx/server.d
if [ "${ARTIFACTS_PROXY_ENABLED:-false}" = "true" ]; then
  ln -sf /etc/nginx/artifacts/proxy.conf /etc/nginx/server.d/proxy.conf
  echo "$0: proxy locations enabled"
else
  rm -f /etc/nginx/server.d/proxy.conf
  echo "$0: proxy locations disabled"
fi
