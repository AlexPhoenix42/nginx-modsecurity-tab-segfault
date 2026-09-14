#!/usr/bin/env bash
#
# Full test matrix: same base image, same libmodsecurity, three different
# nginx-modsecurity connector binaries. Shows that the tab segfault is
# independent of the connector version.
#
# Usage:
#   ./matrix.sh
#
# Exit codes:
#   0  matrix completed
#   2  prerequisite missing (docker not found)

set -u

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found" >&2
    exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- build the two rebuilt connectors --------------------------------------

build_image() {
    local tag="$1"
    local version="$2"

    if docker image inspect "$tag" >/dev/null 2>&1; then
        echo "image $tag already exists, skipping build"
        return
    fi

    echo "building $tag (connector $version) ..."
    docker build \
        -f Dockerfile.matrix \
        --build-arg MODSEC_NGINX_VERSION="$version" \
        -t "$tag" .
}

echo "==> preparing images"
echo

build_image modsec-test:v1.0.3 v1.0.3
build_image modsec-test:v1.0.4 v1.0.4

echo

# --- test inputs -----------------------------------------------------------

printf 'SecAuditLog\t/tmp/audit.log\n' > "$TMP/tab.conf"
printf 'SecAuditLog /tmp/audit.log\n'  > "$TMP/space.conf"

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

test_case() {
    local image="$1"
    local rules="$2"

    docker run --rm \
        -v "$rules:/tmp/rules.conf:ro" \
        -v "$TMP/nginx.conf:/tmp/nginx.conf:ro" \
        --entrypoint sh \
        "$image" -c 'nginx -t -c /tmp/nginx.conf >/dev/null 2>&1; echo $?' \
        2>/dev/null
}

# --- run matrix ------------------------------------------------------------

printf '%-35s | %-25s | %-5s | %-5s\n' "image" "connector" "tab" "space"
printf '%-35s-+-%-25s-+-%-5s-+-%-5s\n' "-----------------------------------" "-------------------------" "-----" "-----"

run_row() {
    local image="$1"
    local label="$2"

    local tab_code space_code
    tab_code=$(test_case "$image" "$TMP/tab.conf")
    space_code=$(test_case "$image" "$TMP/space.conf")

    printf '%-35s | %-25s | %-5s | %-5s\n' "$image" "$label" "$tab_code" "$space_code"
}

run_row owasp/modsecurity:nginx-alpine "v1.0.3 (prebuilt)"
run_row modsec-test:v1.0.3             "v1.0.3 (rebuilt)"
run_row modsec-test:v1.0.4             "v1.0.4 (rebuilt)"

echo
echo "expect: tab column all 139, space column all 0."

