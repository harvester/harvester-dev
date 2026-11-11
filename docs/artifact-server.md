# Artifact server

The artifact server is an nginx container. `task build` / `task up` start it
automatically once Terraform has created the management bridge. It listens
only on the management bridge IP (`networks.mgmt.bridge_ip`), port `8787`, and
node VMs reach it at `artifact_server_url` (default `http://10.0.10.1:8787`).

- `task artifacts-up`: rebuild and restart the container. The management
  bridge must exist.
- `task artifacts-down`: remove the container. `task clean` runs this too.
  Downloaded ISOs and images are kept.
- Set `artifacts.server_enabled: false` in `config.yaml` to skip starting
  it. This turns off the proxy as well.
- The [proxy](#proxy) is off by default. Set `artifacts.proxy_enabled: true`
  to turn it on.

## Local artifacts

| Path | Serves |
|---|---|
| `/isos/` | `./artifacts/isos` |
| `/images/` | `./artifacts/images` |

Directory listing is enabled, so you can browse them in a web browser.

## Proxy

The server can also fetch a file from another HTTP(S) server and pass it on.
Use this when node VMs can reach the artifact server but not the original
server. For example, the original server may sit on a network that only the
host can reach.

The proxy is off by default. To turn it on, set this in `config.yaml` and
run `task artifacts-up`:

```yaml
artifacts:
  proxy_enabled: true
```

When it's off, the proxy paths return `404 Not Found`.

| Request | Fetches | TLS certificate check |
|---|---|---|
| `/proxy/<host>/<path>` | `http://<host>/<path>` | n/a |
| `/proxy_ssl/<host>/<path>` | `https://<host>/<path>` | Checked against the system CA bundle |
| `/proxy_ssl_insecure/<host>/<path>` | `https://<host>/<path>` | Not checked; accepts self-signed certificates |

- `<host>` can be an IP address or a hostname, with an optional port
  (`host:port`). Hostnames are resolved with the DNS servers in the
  container's `/etc/resolv.conf`.
- Query strings are passed to the original server.
- Responses are streamed, not saved to disk first, so large ISOs are fine.
- Redirects from the original server are returned to the client as-is.

Examples:

```sh
# http://10.10.0.100/test.iso
curl -O http://10.0.10.1:8787/proxy/10.10.0.100/test.iso

# https://releases.example.com/v1.8.0/harvester.iso (CA-signed)
curl -O http://10.0.10.1:8787/proxy_ssl/releases.example.com/v1.8.0/harvester.iso

# https://10.10.0.100:8443/test.iso (self-signed)
curl -O http://10.0.10.1:8787/proxy_ssl_insecure/10.10.0.100:8443/test.iso
```

### Boot or upgrade from a remote release

Two tasks point `config.yaml` at a release server, so you don't have to
download the files first. They take the same options as each other and are
the remote counterparts of `select-install-iso` / `select-upgrade-iso`:

| Task | Sets |
|---|---|
| `select-install-remote-iso` | `harvester_version`, `harvester_iso_url`, `harvester_kernel_url`, `harvester_ramdisk_url`, `harvester_rootfs_url` |
| `select-upgrade-remote-iso` | `tests.upgrade.iso_url` |

With `--proxy`, the URLs use the proxy paths above. This needs
`artifacts.proxy_enabled: true`:

```sh
# http://10.0.10.1:8787/proxy_ssl/releases.rancher.com/harvester/v1.8.1/...
task select-install-remote-iso -- --proxy v1.8.1
task select-upgrade-remote-iso -- --proxy v1.8.2

# Self-signed release server
task select-install-remote-iso -- --release-server https://10.10.0.100/harvester --proxy-insecure v1.8.1
```

The release server defaults to `harvester_release_url`, and file names use
`harvester_release_prefix`. The scripts send a HEAD request for each file
first and leave `config.yaml` unchanged if a file they set is missing. The
checksum file and `version.yaml` are skipped if they're missing. The check
goes from the host running the script straight to the release server, not
through the proxy, so the artifact server doesn't need to be up yet. With
`--proxy`, a redirect from the release server counts as an error, because
VMs would follow it to the remote host directly. `--proxy-insecure` skips
certificate verification in the check too. Pass `--skip-check` to set the
URLs without checking, e.g. when this host can't reach the release server.

### Troubleshooting

The proxy returns `502 Bad Gateway` when it can't fetch the file. Check the
container log for the cause:

```sh
docker logs <prefix>-artifacts-server
```

Common messages:

- `could not be resolved (3: Host not found)`: the container's DNS server
  doesn't know the hostname. Use an IP address instead.
- `upstream SSL certificate verify error: (18:self-signed certificate)`: the
  server uses a self-signed certificate. Use `/proxy_ssl_insecure/` instead.

> **Warning:** the proxy fetches from any host that a client names, using
> the host machine's network access. The server listens only on the
> management bridge, so only the host and VMs on that network can use it.
> Don't publish it on other interfaces.

## Configuration

- [artifacts/default.conf](../artifacts/default.conf): the nginx server
  config. The image installs it as a template, and the container fills in the
  `${NGINX_LOCAL_RESOLVERS}` DNS setting when it starts. Use it through the
  image, not as a plain nginx config file.
- [artifacts/proxy.conf](../artifacts/proxy.conf): the proxy locations.
  [artifacts/40-artifacts-proxy.sh](../artifacts/40-artifacts-proxy.sh)
  includes them at startup when `artifacts.proxy_enabled` is true.
- [artifacts/Dockerfile](../artifacts/Dockerfile): builds the image.

After you change any of these files, run `task artifacts-up` again to
rebuild and restart the container.
