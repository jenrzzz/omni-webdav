#!/bin/sh
set -e

# Materialize the WebDAV Basic-auth file at runtime so no credential lives in the image/repo.
# Provide ONE of (base64 form preferred — APR1 hashes contain '$' which interpolates badly):
#   WEBDAV_HTPASSWD_B64 - base64 of the htpasswd line(s)
#   WEBDAV_HTPASSWD     - raw htpasswd line(s), e.g. 'jenner:$apr1$...'
PWFILE=/etc/apache2/webdav.password

if [ -n "${WEBDAV_HTPASSWD_B64:-}" ]; then
  printf '%s' "$WEBDAV_HTPASSWD_B64" | base64 -d > "$PWFILE"
elif [ -n "${WEBDAV_HTPASSWD:-}" ]; then
  printf '%s\n' "$WEBDAV_HTPASSWD" > "$PWFILE"
else
  echo "FATAL: set WEBDAV_HTPASSWD_B64 or WEBDAV_HTPASSWD (an htpasswd line like 'user:\$apr1\$...')." >&2
  exit 1
fi

chown root:www-data "$PWFILE"
chmod 640 "$PWFILE"

exec "$@"
