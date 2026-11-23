# Aurum dedicated multiplayer server (Godot 4.7.2 headless, ENet UDP 7777).
# Build from the repository root:
#   docker build -f server/Dockerfile -t aurum-server .
#   docker run -d --restart unless-stopped -p 7777:7777/udp --name aurum aurum-server
FROM ubuntu:24.04

ARG GODOT_VERSION=4.7.2
ARG GODOT_RELEASE=stable

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /opt \
 && mv /opt/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64 /opt/godot \
 && chmod +x /opt/godot \
 && rm /tmp/godot.zip

COPY AurumGodot /game
# Import once at build time so the server starts fast.
RUN /opt/godot --headless --path /game --import > /tmp/import.log 2>&1 || true

RUN useradd --create-home aurum && chown -R aurum /game
USER aurum

ENV AURUM_PORT=7777 \
    AURUM_LOBBY_SECONDS=30
EXPOSE 7777/udp

CMD /opt/godot --headless --path /game res://scenes/server.tscn -- --server --port=${AURUM_PORT} --lobby-seconds=${AURUM_LOBBY_SECONDS}
