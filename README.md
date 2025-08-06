# Torrent-Streambox
A Self-Hosted MP3 Archive + WebTorrent Streaming Server

Mirror: https://zchg.org/t/torrent-streambox-a-self-hosted-mp3-archive-webtorrent-streaming-server/782

## Version 0.0.4 (ALPHA, NO PROMISES)

## 🧩 What This Is: A Self-Contained Media Archive and Streaming Torrent Server

This is a **self-hosted, Dockerized provisioning script** that creates a full-featured media delivery system using torrents. It allows users to **seed MP3 files**, serve them as torrents via an auto-generated index, and **stream them in-browser** via WebTorrent—all from a single command.

It includes:

* A clean **web frontend** to list, stream, and download `.torrent` files.
* **Automatic torrent generation** from your MP3 files.
* **Optional Tor integration** for anonymous `.onion` hosting.
* Full Docker deployment including:
  * WebTorrent Hybrid
  * `mktorrent`
  * Nginx
  * Supervisor for process control
* Pluggable config via environment variables or `config.sh`.

---

## ✨ Why This Is Novel

1. **Zero-Install for End Users**: No torrent client needed—users can stream or download directly from the browser.
2. **Autonomous Seeder**: Automatically generates `.torrent` files and seeds MP3s via `webtorrent-hybrid`.
3. **Web Archive Ready**: Produces a self-contained web UI for easy publishing and access.
4. **Privacy-First Optionality**: Fully supports Tor via `dperson/torproxy`, including `.onion` services out of the box.
5. **Generic + Configurable**: Deploys anywhere with overridable defaults for all paths, titles, and networking.
6. **Minimal Setup, Maximum Power**: One script builds a full archival torrent streamer stack.

---

## 🔧 What It's Used For

* Hosting and sharing audio archives (lectures, podcasts, music) as torrents.
* Creating a private, peer-to-peer streaming site for your media.
* Building a self-sufficient media distribution platform with no centralized dependencies.
* Providing streaming access to media over `.onion` with privacy.
* Preserving and seeding MP3 collections without third-party hosting.

---

## 🚀 Instructions for Deployment

### 1. **Prepare Your MP3s**

Place `.mp3` files in your desired directory. Defaults to:

bash

```
~/mp3s
```

Or override via environment:

bash
```
export MP3_DIR="/path/to/your/mp3s"
```

### 2. **Run the Script**

Save the provisioning script and run it:

bash

```
chmod +x provision.sh
./provision.sh
```

This sets up:

* Directory structure
* Dockerfile + `docker-compose.yml`
* Nginx config
* Seeding script
* Frontend HTML
* Supervisor config

### 3. **Start Docker Containers**

Navigate to the Docker project and start:

bash

```
cd ~/streamer_docker
docker-compose build
docker-compose up -d
```

### 4. **Access the Web UI**

* Open `http://your-host/media/stream/` in a browser to stream MP3s
* Open `http://your-host/media/torrents/` to download `.torrent` files

### 5. **Check Tor Onion Address (Optional)**

If `USE_TOR_PROXY=true`:

bash

```
docker exec torproxy cat /var/lib/tor/hidden_service/hostname
```

Then visit the `.onion` site in Tor Browser.

---

## 🧰 Customize via Config

You can override any default by setting:

bash

```
export BASE_URL="/my-media"
export ARCHIVE_TITLE="My Podcast Archive"
export USE_TOR_PROXY="false"
```

Or create a `config.sh` file and place it next to the script:

bash

```
MP3_DIR="/data/mp3s"
ARCHIVE_TITLE="Legacy Audio Collection"
USE_TOR_PROXY="false"
```

---

## 🪵 Logs

Logs for all services (Nginx, seeder, supervisord) are stored in:

bash
```
/var/log/streamer
```

---

## 🛠 Requirements

* Docker + Docker Compose
* Bash (Linux or WSL/macOS)
* MP3s you own or have rights to distribute

---

## Troubleshoot

Myself, I'm in Ubuntu, it won't work.  
"-bash: ./provision.sh: cannot execute: required file not found"

You need to:
```
apt-get update && apt-get install dos2unix -y
```
```
dos2unix provision.sh
```

---

## 📜 License & Attribution
https://zchg.org/t/legal-notice-copyright-applicable-ip-and-licensing-read-me/440
