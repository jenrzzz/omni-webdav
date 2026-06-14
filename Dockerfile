# OmniFocus WebDAV sync server (Apache mod_dav).
# Replaces the old custom-nginx (dav-ext) build on luna; runs on Coolify behind Traefik.
#
# No credential lives in this image or repo — the htpasswd is materialized at runtime by
# entrypoint.sh from the WEBDAV_HTPASSWD_B64 (or WEBDAV_HTPASSWD) env var.
#
# mod_headers rewrites the WebDAV Destination header (https->http) so MOVE works behind
# Traefik's TLS termination (OmniFocus uploads to a temp name then MOVEs into place;
# without this mod_dav returns 502 "Destination URI refers to different scheme or port").
# LOCK is intentionally not configured — the old nginx had none and OmniFocus syncs fine.

FROM debian:bookworm-slim

RUN apt-get update \
 # wget + curl are only here for healthchecks. Coolify injects its OWN compose-level probe that
 # uses **wget** (it overrides the image HEALTHCHECK below) and, on the slim image, failed with
 # "wget: not found". Coolify's wget probe also exits non-zero on any non-2xx, so it can't accept
 # the DAV root's 401 — that's why the /healthz endpoint (200) exists. curl backs the explicit
 # HEALTHCHECK; both binaries are tiny.
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2 curl wget \
 && rm -rf /var/lib/apt/lists/* \
 && a2enmod dav dav_fs auth_basic authn_file authn_core authz_core authz_user headers \
 && a2dissite 000-default \
 && rm -rf /var/www/html \
 && mkdir -p /var/lib/dav \
 && chown -R www-data:www-data /var/lib/dav \
 # Health endpoint payload (served unauthenticated at /healthz — see webdav.conf).
 && mkdir -p /var/www/health \
 && printf 'ok\n' > /var/www/health/index.html \
 # Send Apache's file logs to the container's stdout/stderr so `docker logs` / Coolify show
 # them (Apache logs to files by default, which is why `docker logs` was empty).
 && ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stdout /var/log/apache2/other_vhosts_access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

COPY webdav.conf   /etc/apache2/sites-available/webdav.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && a2ensite webdav

EXPOSE 80
# Probe the unauthenticated /healthz (200). -f makes any non-2xx a failure. This mirrors what
# Coolify's compose-level probe (which overrides this one) does, so behaviour matches whether
# the image runs under Coolify or standalone.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS -o /dev/null http://localhost/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# apache2ctl (not bare apache2) so /etc/apache2/envvars is sourced.
CMD ["apache2ctl", "-DFOREGROUND"]
