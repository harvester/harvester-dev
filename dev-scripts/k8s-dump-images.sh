#!/usr/bin/env bash
set -euo pipefail

# List every pod's containers and images, organized by node > namespace > pod > container.
# Requires: kubectl (KUBECONFIG exported), yq (mikefarah/yq v4+)

# Set to 1 to prepend "docker.io" to images that have no explicit registry.
PREPEND_DOCKER_IO=${PREPEND_DOCKER_IO:-1}

# Set to 1 to colorize image registry names in the output.
COLOR_OUTPUT=${COLOR_OUTPUT:-1}

kubectl get pods --all-namespaces -o json \
  | yq -r '
      .items[] |
      select(.spec.nodeName != null) |
      .spec.nodeName + "|" + .metadata.namespace + "|" + .metadata.name + "|" +
      (.spec.containers[] | .name + "|" + .image)
    ' \
  | sort \
  | awk -F'|' -v prepend_docker_io="$PREPEND_DOCKER_IO" -v color_output="$COLOR_OUTPUT" '
      # ANSI colors assigned per registry; new registries get the next color in rotation.
      function registry_color(reg,    c) {
          if (!color_output) return ""
          if (!(reg in reg_color)) {
              # Cycle through: cyan, green, yellow, magenta, blue, red, bright-cyan, bright-green
              split("36 32 33 35 34 31 96 92", palette, " ")
              color_idx++
              reg_color[reg] = palette[(color_idx - 1) % 8 + 1]
          }
          return "\033[" reg_color[reg] "m"
      }
      function reset() { return color_output ? "\033[0m" : "" }

      function normalize_image(img,    parts, first, n) {
          if (!prepend_docker_io) return img
          n = split(img, parts, "/")
          if (n == 1) {
              return "docker.io/library/" img
          }
          first = parts[1]
          if (first ~ /\./ || first ~ /:/ || first == "localhost") {
              return img
          }
          return "docker.io/" img
      }

      function extract_registry(img,    parts, first, n) {
          n = split(img, parts, "/")
          if (n == 1) return "docker.io"
          first = parts[1]
          if (first ~ /\./ || first ~ /:/ || first == "localhost") return first
          return "docker.io"
      }

      function colorize_image(img,    reg, col, res) {
          if (!color_output) return img
          reg = extract_registry(img)
          col = registry_color(reg)
          # Color only the registry prefix, reset after it
          if (index(img, reg "/") == 1) {
              res = col reg reset() substr(img, length(reg) + 1)
          } else {
              res = col img reset()
          }
          return res
      }

      BEGIN { prev_node = ""; prev_ns = ""; prev_pod = ""; color_idx = 0 }
      {
          node = $1; ns = $2; pod = $3; ctr = $4; img = normalize_image($5)
          if (node != prev_node) {
              if (prev_node != "") print ""
              print node ":"
              prev_node = node; prev_ns = ""; prev_pod = ""
          }
          if (ns != prev_ns) {
              print "  " ns
              prev_ns = ns; prev_pod = ""
          }
          if (pod != prev_pod) {
              print "      " pod
              prev_pod = pod
          }
          printf "           %-45s %s\n", ctr, colorize_image(img)
      }
    '
