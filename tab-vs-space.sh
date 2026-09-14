#!/usr/bin/env bash
#
# Minimal reproduction: a single tab character in a ModSecurity rules file
# causes a segfault during config parsing.
#
# Usage:
#   ./tab-vs-space.sh [IMAGE]
#
# Default IMAGE: owasp/modsecurity:nginx-alpine
#
# Exit codes:
#   0  bug reproduced (tab crashes, space succeeds)
#   1  bug NOT reproduced
#   2  prerequisite missing (docker not found)

set -u

IMAGE="${1:-owasp/modsecurity:nginx-alpine}"

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found" >&2
    exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- test inputs -----------------------------------------------------------

# Tab between directive and value
printf 'SecAuditLog\t/tmp/audit.log\n' > "$TMP/tab.conf"

# Same directive, space instead of tab
printf 'SecAuditLog /tmp/audit.log\n' > "$TMP/space.conf"

# Minimal nginx config that loads ModSecurity and points at the rules file
cat > "$TMP/nginx.conf" <<'EOF'
load_module modules/ngx_http_modsecurity_module.so;
events {}
http {
    server {
        listen 80;
        modsecurity on;
        modsecurity_rules_file /tmp/rules.conf;
    }
}
EOF

# --- harness ---------------------------------------------------------------

echo "image: $IMAGE"
echo

run_case() {
    local label="$1"
    local rules_file="$2"

    echo "--- $label ---"
    echo "rules file (cat -A):"
    cat -A "$rules_file"
    echo

    docker run --rm \
        -v "$rules_file:/tmp/rules.conf:ro" \
        -v "$TMP/nginx.conf:/tmp/nginx.conf:ro" \
        --entrypoint sh \
        "$IMAGE" -c 'nginx -t -c /tmp/nginx.conf'

    local code=$?
    echo "exit: $code"
    echo
    return $code
}

run_case "tab in rules file" "$TMP/tab.conf"
tab_code=$?

run_case "space in rules file" "$TMP/space.conf"
space_code=$?

# --- verdict ---------------------------------------------------------------

echo "--- verdict ---"
echo "tab   -> exit $tab_code"
echo "space -> exit $space_code"
echo

if [ "$tab_code" -ne 0 ] && [ "$space_code" -eq 0 ]; then
    echo "bug reproduced: tab crashes, space succeeds."
    exit 0
else
    echo "bug NOT reproduced with this image."
    exit 1
fi

