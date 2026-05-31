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
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2 \
 && rm -rf /var/lib/apt/lists/* \
 && a2enmod dav dav_fs auth_basic authn_file authn_core authz_core authz_user headers \
 && a2dissite 000-default \
 && rm -rf /var/www/html \
 && mkdir -p /var/lib/dav \
 && chown -R www-data:www-data /var/lib/dav

COPY webdav.conf   /etc/apache2/sites-available/webdav.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && a2ensite webdav

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# apache2ctl (not bare apache2) so /etc/apache2/envvars is sourced.
CMD ["apache2ctl", "-DFOREGROUND"]
