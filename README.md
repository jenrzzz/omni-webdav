# omni-webdav

A tiny Apache `mod_dav` WebDAV server for **OmniFocus sync** (`omni.jfave.com`), built to run on
Coolify behind Traefik. It replaces the old custom-nginx (`dav`/`dav-ext`) build that ran on the
luna Linode being decommissioned.

**No secrets live in this repo.** The HTTP Basic-auth file is materialized at runtime from an
environment variable, so the image/repo can be public.

## How it works
- `Dockerfile` — Debian + Apache with `dav dav_fs auth_basic authn_file headers` enabled.
- `entrypoint.sh` — writes `/etc/apache2/webdav.password` from `WEBDAV_HTPASSWD_B64` (base64 of an
  htpasswd line) or `WEBDAV_HTPASSWD` (raw), then starts Apache.
- `webdav.conf` — `DAV On` over `/var/lib/dav`, Basic auth, and the key bit:
  `RequestHeader edit Destination ^https: http: early` so WebDAV `MOVE` works behind Traefik's TLS
  termination (OmniFocus uploads to a temp name then `MOVE`s it into place). LOCK is intentionally
  omitted — the old nginx had none and OmniFocus syncs fine without it.
- Listens on **:80**; persistent data lives at **/var/lib/dav**.

## Credentials
Provide `WEBDAV_HTPASSWD_B64` = base64 of an htpasswd line. Base64 is preferred because APR1 hashes
contain `$`, which interpolates badly through compose/shell layers.

```sh
# reuse an existing APR1 hash (no client re-auth):
printf '%s\n' 'jenner:$apr1$....' | base64
# or make a fresh credential:
htpasswd -nB jenner | base64
```

## Deploy on Coolify
Docker build pack = **Dockerfile**, port **80**, domain **omni.jfave.com**, with:
- env `WEBDAV_HTPASSWD_B64` (set as a secret),
- persistent storage host `/data/coolify/omni` → container `/var/lib/dav`.

## Migrating data from luna + DNS cutover
See the runbook in the `infra` notes, in short:
```sh
# 1. copy the existing sync data into the bind mount on the Coolify host:
ssh root@5.78.183.213 'mkdir -p /data/coolify/omni'
rsync -avz root@50.116.11.109:/var/www/omni/ root@5.78.183.213:/data/coolify/omni/
ssh root@5.78.183.213 'chown -R 33:33 /data/coolify/omni'   # www-data on Debian

# 2. smoke test (before DNS flip) — MOVE must return 201/204, not 502:
curl -u jenner:PASS -X PROPFIND https://<host>/ -H 'Depth: 1'
curl -u jenner:PASS -T ./a https://<host>/a
curl -u jenner:PASS -X MOVE https://<host>/a -H 'Destination: https://<host>/b'

# 3. flip omni.jfave.com A record 50.116.11.109 -> 5.78.183.213; Traefik issues the LE cert.
```
OmniFocus clients need no changes when the existing hash is reused — same URL, same password.

## Local testing
```sh
export WEBDAV_HTPASSWD_B64=$(printf '%s\n' 'jenner:$apr1$....' | base64)
docker compose up --build
curl -u jenner:PASS -X PROPFIND http://localhost:8080/ -H 'Depth: 1'
```
