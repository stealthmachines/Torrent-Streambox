#!/bin/bash
set -euo pipefail

# === CONFIG — override these via environment variables or a config file ===
# Directory paths for media, torrents, scripts, web root, Docker project, and logs
: ${MP3_DIR:="${HOME}/mp3s"}
: ${TORRENT_DIR:="${HOME}/torrents"}
: ${SCRIPTS_DIR:="${HOME}/scripts"}
: ${ARCHIVE_ROOT:="/var/www/public"}
: ${DOCKER_PROJECT_DIR:="${HOME}/streamer_docker"}
: ${LOG_DIR:="/var/log/streamer"}
# User and group for ownership (e.g., for web server)
: ${TARGET_USER:="www-data"}
: ${TARGET_GROUP:="www-data"}
# Branding and URL configuration
: ${ARCHIVE_TITLE:="Media Archive"}
: ${BASE_URL:="/media"}
# Tor proxy configuration
: ${USE_TOR_PROXY:="true"}
# Torrent tracker list (space-separated for flexibility)
: ${TRACKERS:="udp://tracker.opentrackr.org:1337/announce udp://open.tracker.cl:1337/announce udp://tracker.torrent.eu.org:451/announce"}

# Load optional config file for user overrides
CONFIG_FILE="./config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

echo "Starting full provisioning..."

# 1. Create necessary directories & fix ownership
mkdir -p "$MP3_DIR" "$TORRENT_DIR" "$SCRIPTS_DIR" "$ARCHIVE_ROOT" "$DOCKER_PROJECT_DIR/streamer/public" "$DOCKER_PROJECT_DIR/streamer/nginx" "$DOCKER_PROJECT_DIR/tor" "$LOG_DIR"
chown -R "${TARGET_USER}:${TARGET_GROUP}" "$MP3_DIR" "$TORRENT_DIR" "$SCRIPTS_DIR" "$ARCHIVE_ROOT" "$DOCKER_PROJECT_DIR" "$LOG_DIR"
chmod -R u+rwX "$MP3_DIR" "$TORRENT_DIR" "$SCRIPTS_DIR" "$ARCHIVE_ROOT" "$DOCKER_PROJECT_DIR" "$LOG_DIR"

# 2. Archival landing page
cat > "$ARCHIVE_ROOT/index.html" <<EOF
<!DOCTYPE html>
<html>
<head><title>${ARCHIVE_TITLE}</title></head>
<body>
  <h1>Welcome to ${ARCHIVE_TITLE}</h1>
  <ul>
    <li><a href="${BASE_URL}/stream/">Listen / Stream MP3s</a></li>
    <li><a href="${BASE_URL}/torrents/">Download Torrents</a></li>
  </ul>
</body>
</html>
EOF

# 3. docker-compose.yml
cat > "$DOCKER_PROJECT_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  tor:
    build: ./tor
    container_name: torproxy
    restart: unless-stopped
    ports:
      - "9050:9050"
    volumes:
      - tor_data:/var/lib/tor
      - $DOCKER_PROJECT_DIR/tor/torrc:/etc/tor/torrc:ro
    healthcheck:
      test: ["CMD", "curl", "-s", "--socks5", "localhost:9050", "http://check.torproject.org"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    deploy:
      mode: replicated
      replicas: $( [ "${USE_TOR_PROXY}" == "true" ] && echo 1 || echo 0 )

  streamer:
    build: ./streamer
    container_name: torrent_streamer
    restart: unless-stopped
    volumes:
      - ${MP3_DIR}:/media/mp3s:ro
      - ${TORRENT_DIR}:/var/www/html/torrents
      - ${SCRIPTS_DIR}:/app-scripts:ro
      - ${LOG_DIR}:/var/log/streamer
    environment:
      - USE_TOR_PROXY=${USE_TOR_PROXY:-true}
    network_mode: $( [ "${USE_TOR_PROXY}" == "true" ] && echo "service:tor" || echo "bridge" )
    command: /bin/bash -c "/app-scripts/seed-and-run.sh && /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf"
EOF
# Conditionally add depends_on if USE_TOR_PROXY is true
if [ "${USE_TOR_PROXY}" == "true" ]; then
  cat >> "$DOCKER_PROJECT_DIR/docker-compose.yml" <<EOF
    depends_on:
      tor:
        condition: service_healthy
EOF
fi

cat >> "$DOCKER_PROJECT_DIR/docker-compose.yml" <<EOF
volumes:
  tor_data:
EOF

# 4. Tor Dockerfile
cat > "$DOCKER_PROJECT_DIR/tor/Dockerfile" <<EOF
FROM dperson/torproxy
RUN apk add --no-cache curl && \
    chown -R root:root /var/lib/tor
EOF

# 5. Tor torrc configuration
cat > "$DOCKER_PROJECT_DIR/tor/torrc" <<EOF
SocksPort 0.0.0.0:9050
HiddenServiceDir /var/lib/tor/hidden_service
HiddenServicePort 80 127.0.0.1:8080
EOF

# 6. Streamer Dockerfile
cat > "$DOCKER_PROJECT_DIR/streamer/Dockerfile" <<EOF
FROM node:18

RUN apt-get update && apt-get install -y mktorrent nginx supervisor

RUN npm install -g @mapbox/node-pre-gyp webtorrent-hybrid

RUN mkdir -p /var/www/html/torrents ${LOG_DIR} && \
    chown -R ${TARGET_USER}:${TARGET_GROUP} /var/www/html/torrents ${LOG_DIR} && \
    chmod -R u+rwX /var/www/html/torrents ${LOG_DIR}

COPY public /var/www/html
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY seed-and-run.sh /app-scripts/seed-and-run.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod +x /app-scripts/seed-and-run.sh

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOF

# 7. nginx.conf
cat > "$DOCKER_PROJECT_DIR/streamer/nginx/nginx.conf" <<EOF
user ${TARGET_USER};
worker_processes auto;
pid /run/nginx.pid;

events {
  worker_connections 768;
}

http {
  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;

  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  access_log ${LOG_DIR}/nginx_access.log;
  error_log ${LOG_DIR}/nginx_error.log;

  server {
    listen 80;
    server_name localhost;

    root /var/www/html;
    index index.html;

    location ${BASE_URL}/torrents/ {
      alias /var/www/html/torrents/;
      autoindex on;
    }

    location ${BASE_URL}/stream/ {
      alias /var/www/html/;
      try_files \$uri \$uri/ /index.html;
    }
  }
}
EOF

# 8. supervisord.conf
cat > "$DOCKER_PROJECT_DIR/streamer/supervisord.conf" <<EOF
[supervisord]
nodaemon=true
logfile=${LOG_DIR}/supervisord.log
logfile_maxbytes=50MB
logfile_backups=10

[program:nginx]
command=nginx -g "daemon off;"
autorestart=true
stdout_logfile=${LOG_DIR}/nginx_stdout.log
stdout_logfile_maxbytes=10MB
stderr_logfile=${LOG_DIR}/nginx_stderr.log
stderr_logfile_maxbytes=10MB

[program:webtorrent]
command=/bin/bash -c "if ls /media/mp3s/*.mp3 >/dev/null 2>&1; then webtorrent-hybrid seed /media/mp3s/*.mp3 --no-quit --tracker; else echo 'No MP3 files found, skipping seeding'; sleep infinity; fi"
autorestart=true
stdout_logfile=${LOG_DIR}/webtorrent_stdout.log
stdout_logfile_maxbytes=10MB
stderr_logfile=${LOG_DIR}/webtorrent_stderr.log
stderr_logfile_maxbytes=10MB
EOF

# 9. seed-and-run.sh (torrent generator only)
if [ ! -f "$DOCKER_PROJECT_DIR/streamer/seed-and-run.sh" ]; then
cat > "$DOCKER_PROJECT_DIR/streamer/seed-and-run.sh" <<EOF
#!/bin/bash
set -euo pipefail

SOURCE=/media/mp3s
TORDIR=/var/www/html/torrents
LOGFILE=${LOG_DIR}/seed-and-run.log
TRACKERS=(${TRACKERS})

mkdir -p "\$TORDIR"
chmod -R u+rwX "\$TORDIR"
mkdir -p "\$(dirname "\$LOGFILE")"
touch "\$LOGFILE"
chmod u+rw "\$LOGFILE"

echo "[$(date)] Generating .torrent files if missing..." >> "\$LOGFILE"
if ! ls "\$SOURCE"/*.mp3 >/dev/null 2>&1; then
  echo "[$(date)] No MP3 files found in \$SOURCE, skipping torrent generation." >> "\$LOGFILE"
  exit 0
fi

find "\$SOURCE" -maxdepth 1 -type f -iname "*.mp3" | while read -r FILE; do
  NAME="\$(basename "\$FILE" .mp3)"
  TOR="\$TORDIR/\$NAME.torrent"
  if [[ ! -f "\$TOR" ]]; then
    echo "[$(date)] Creating torrent for \$FILE" >> "\$LOGFILE"
    mktorrent_args=()
    for tracker in "\${TRACKERS[@]}"; do
      mktorrent_args+=(-a "\$tracker")
    done
    if mktorrent "\${mktorrent_args[@]}" -o "\$TOR" "\$FILE" >> "\$LOGFILE" 2>&1; then
      echo "[$(date)] Successfully created \$TOR" >> "\$LOGFILE"
    else
      echo "[$(date)] Error creating torrent for \$FILE" >> "\$LOGFILE"
      exit 1
    fi
  else
    echo "[$(date)] Skipping existing: \$TOR" >> "\$LOGFILE"
  fi
done
EOF
  chmod +x "$DOCKER_PROJECT_DIR/streamer/seed-and-run.sh"
fi

# 10. Frontend index.html
cat > "$DOCKER_PROJECT_DIR/streamer/public/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>${ARCHIVE_TITLE}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    #torrent-list { margin: 20px 0; }
    button { margin: 5px; padding: 10px; }
    .error { color: red; }
  </style>
</head>
<body>
  <h1>${ARCHIVE_TITLE}</h1>
  <div id="torrent-list"></div>
  <div id="error" class="error"></div>
  <audio id="player" controls></audio>
  <script src="https://cdn.jsdelivr.net/npm/webtorrent/webtorrent.min.js"></script>
  <script>
    const client = new WebTorrent();
    const errorDiv = document.getElementById('error');
    fetch('${BASE_URL}/torrents/')
      .then(response => {
        if (!response.ok) throw new Error('Failed to fetch torrent list');
        return response.text();
      })
      .then(data => {
        const parser = new DOMParser();
        const htmlDoc = parser.parseFromString(data, 'text/html');
        const links = Array.from(htmlDoc.querySelectorAll('a'))
          .map(a => a.href)
          .filter(href => href.endsWith('.torrent'));
        const list = document.getElementById('torrent-list');
        if (links.length === 0) {
          errorDiv.textContent = 'No torrents found in ${BASE_URL}/torrents/';
          return;
        }
        links.forEach(link => {
          const btn = document.createElement('button');
          btn.textContent = link.split('/').pop();
          btn.onclick = () => {
            client.add(link, torrent => {
              const file = torrent.files.find(f => f.name.endsWith('.mp3'));
              if (file) {
                file.renderTo('#player');
                errorDiv.textContent = '';
              } else {
                errorDiv.textContent = 'No MP3 file found in torrent: ' + link;
              }
            }, err => {
              errorDiv.textContent = 'Error loading torrent: ' + err.message;
            });
          };
          list.appendChild(btn);
        });
      })
      .catch(err => {
        errorDiv.textContent = 'Error fetching torrents: ' + err.message;
      });
  </script>
</body>
</html>
EOF

# Done
echo "✅ Docker setup files created at $DOCKER_PROJECT_DIR"
echo "👉 Run:"
echo "   cd $DOCKER_PROJECT_DIR"
echo "   docker-compose build"
echo "   docker-compose up -d"
if [ "${USE_TOR_PROXY}" == "true" ]; then
  echo "🔍 To check Tor .onion address:"
  echo "   docker exec torproxy cat /var/lib/tor/hidden_service/hostname"
fi
echo "📝 Ensure MP3 files exist in $MP3_DIR"
echo "📜 Logs are written to $LOG_DIR"
echo "🌐 Configure host Nginx to proxy ${BASE_URL}/stream and serve ${BASE_URL}/torrents and ${BASE_URL}"
echo "📋 To customize, set environment variables or create a config.sh file with:"
echo "   MP3_DIR, TORRENT_DIR, SCRIPTS_DIR, ARCHIVE_ROOT, DOCKER_PROJECT_DIR, LOG_DIR"
echo "   TARGET_USER, TARGET_GROUP, ARCHIVE_TITLE, BASE_URL, USE_TOR_PROXY, TRACKERS"
