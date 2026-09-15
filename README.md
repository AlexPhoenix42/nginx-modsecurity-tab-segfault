# nginx-modsecurity-tab-segfault

A single tab character in a ModSecurity rules file causes a segfault during
nginx config parsing on `owasp/modsecurity:nginx-alpine` (libmodsecurity 3.0.8).

## Resolution

Confirmed as a known libmodsecurity bug, fixed in 3.0.15.

> An issue was discovered in libmodsecurity3's config parser. ModSecurity
> could crash in some cases if a config directive used tabs instead of spaces.
>
> A second issue in the config parser could cause an unhandled exception to be
> thrown in several different cases (e.g., unknown token).

- [Changelog](https://github.com/owasp-modsecurity/ModSecurity/blob/v3/master/CHANGES#L32-L33)
- [Fix PR](https://github.com/owasp-modsecurity/ModSecurity/pull/3543) 

Affected: libmodsecurity 3.0.8, as shipped in `owasp/modsecurity:nginx-alpine`
(2022-10-23 build).

Workaround: use spaces, not tabs, in rules files.

Proper fix: upgrade to libmodsecurity 3.0.15+.

The `owasp/modsecurity` image is now archived (Docker Hub points to
`coreruleset/modsecurity-docker-crs`). The replacement image,
`owasp/modsecurity-crs:nginx-alpine`, ships libmodsecurity 3.0.16 and the
fix is present there:

```
$ ./tab-vs-space.sh owasp/modsecurity-crs:nginx-alpine
...
tab   -> exit 0
space -> exit 0
bug NOT reproduced with this image.
```

## What happens

The same directive parses cleanly when separated from its value by a space,
and crashes the process when separated by a tab.

```
SecAuditLog /tmp/audit.log     -> parses
SecAuditLog<TAB>/tmp/audit.log -> SIGSEGV
```

This affects any `Sec*` directive. It is not specific to `SecAuditLog`,
to directive order, or to the `nginx-modsecurity` connector version.

## Requirements

- Docker
- A shell

## Reproduction

```sh
./tab-vs-space.sh
```

Expected output:

```
--- tab in rules file ---
rules file (cat -A):
SecAuditLog^I/tmp/audit.log$

exit: 139

--- space in rules file ---
rules file (cat -A):
SecAuditLog /tmp/audit.log$

2026/09/14 18:10:50 [notice] 1#1: ModSecurity-nginx v1.0.3 (rules loaded inline/local/remote: 0/0/0)
nginx: the configuration file /tmp/nginx.conf syntax is ok
nginx: configuration file /tmp/nginx.conf test is successful
exit: 0

--- verdict ---
tab   -> exit 139
space -> exit 0

bug reproduced: tab crashes, space succeeds.
```

The script accepts an image tag as its first argument, so it can be pointed
at any image built on the same base:

```sh
./tab-vs-space.sh modsec-test:v1.0.4
```

## Full matrix

```sh
./matrix.sh
```

Builds two additional images from `Dockerfile.matrix` (connector v1.0.3 and
v1.0.4, both compiled from source against the same base image) and runs the
tab-vs-space test against each. First run takes roughly 20 minutes; later
runs reuse the images.

```
image                               | connector                 | tab   | space
------------------------------------+---------------------------+-------+------
owasp/modsecurity:nginx-alpine      | v1.0.3 (prebuilt)         | 139   | 0
modsec-test:v1.0.3                  | v1.0.3 (rebuilt)          | 139   | 0
modsec-test:v1.0.4                  | v1.0.4 (rebuilt)          | 139   | 0
```

All three images share the same base (`owasp/modsecurity:nginx-alpine`),
the same nginx version (1.22.1), and the same libmodsecurity version (3.0.8).
The only difference between rows is the connector binary. The crash does not
depend on it.

## Environment

Tested against:

- Image: `owasp/modsecurity:nginx-alpine`
  (`sha256:c9c6652f254743f85c0249d59fd31b6e31c46676ae3baeef312cf056eba600b3`,
  built 2022-10-23)
- nginx 1.22.1
- libmodsecurity 3.0.8
- ModSecurity-nginx v1.0.3 (prebuilt)

Also verified against:

- Image: `owasp/modsecurity-crs:nginx-alpine`
- libmodsecurity 3.0.16
- ModSecurity-nginx v1.0.4
- Result: no crash

## Notes

Rules files are parsed by libmodsecurity, not by the connector — the connector
passes a file path and lets libmodsecurity handle the contents. The connector
version has no effect on the crash, which is consistent with the bug being in
libmodsecurity itself (fixed in 3.0.15).

## License

GPLv3

