# =============================================================================
# Asterisk 22 (Sangoma / FreePBX official Debian 12 packages)
# Built for a single IP-authenticated SIP trunk. No FreePBX GUI, no AMI/HTTP.
# =============================================================================
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Karachi

# Base tooling + Asterisk 22 from the official Sangoma/FreePBX bookworm repo.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates gnupg software-properties-common wget curl \
        procps iproute2 dnsutils tcpdump sngrep nano less tzdata \
 && ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone \
 && wget -O /tmp/aptly-pubkey.asc http://deb.freepbx.org/gpg/aptly-pubkey.asc \
 && gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/freepbx.gpg /tmp/aptly-pubkey.asc \
 && add-apt-repository -y -S "deb [ arch=amd64 ] http://deb.freepbx.org/freepbx17-prod bookworm main" \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        asterisk22 asterisk22-core asterisk22-configs libxslt1.1 liburiparser1 \
 # Snapshot package defaults so empty host bind-mounts can be seeded at runtime
 # (otherwise mounting empty ./lib over /var/lib/asterisk hides sounds/keys).
 && mkdir -p /opt/asterisk-defaults \
 && cp -a /var/lib/asterisk   /opt/asterisk-defaults/var-lib-asterisk \
 && cp -a /var/spool/asterisk /opt/asterisk-defaults/var-spool-asterisk \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/aptly-pubkey.asc

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/asterisk", "-f", "-U", "asterisk", "-G", "asterisk", "-vvv"]
