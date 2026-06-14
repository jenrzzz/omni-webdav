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
 # uses **wget** (it overrides the image HEALTHCHECK below and fails with "wget: not found" on
 # the slim image); curl backs the explicit HEALTHCHECK. Both are tiny. Coolify's probe honours
 # the configured 401 return code — it just needs the binary present.
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2 curl wget \
 && rm -rf /var/lib/apt/lists/* \
 && a2enmod dav dav_fs auth_basic authn_file authn_core authz_core authz_user headers \
 && a2dissite 000-default \
 && rm -rf /var/www/html \
 && mkdir -p /var/lib/dav \
 && chown -R www-data:www-data /var/lib/dav \
 # Send Apache's file logs to the container's stdout/stderr so `docker logs` / Coolify show
 # them (Apache logs to files by default, which is why `docker logs` was empty).
 && ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stdout /var/log/apache2/other_vhosts_access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

COPY webdav.conf   /etc/apache2/sites-available/webdav.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && a2ensite webdav

EXPOSE 80
# The DAV root requires auth, so an unauthenticated GET / returns 401 — that IS healthy here.
# Check for exactly 401 (don't use `curl -f`, which would treat 401 as a failure). An explicit
# HEALTHCHECK is deterministic regardless of Coolify's generated-command format / version.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost/)" = "401" ] || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# apache2ctl (not bare apache2) so /etc/apache2/envvars is sourced.
CMD ["apache2ctl", "-DFOREGROUND"]
