# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Steam Selkies version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="df-steam"

# App title
ENV TITLE="Steam"

RUN \
  echo "**** validate arch ****" && \
  ARCH="$(dpkg --print-architecture)" && \
  if [ "${ARCH}" != "amd64" ]; then \
    echo "This image only supports amd64 (detected: ${ARCH})." && \
    echo "If you're building on a different host arch, use your engine's cross-build flag (e.g. docker --platform=linux/amd64)." && \
    exit 1; \
  fi && \
  echo "**** add icon ****" && \
  curl -fL -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/steam-logo.png \
    || true && \
  echo "**** enable contrib/non-free repos (Debian) ****" && \
  if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
    sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources || true; \
  elif [ -f /etc/apt/sources.list ]; then \
    sed -i 's/ main$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list || true; \
  fi && \
  echo "**** install Steam + Sunshine prereqs ****" && \
  dpkg --add-architecture i386 && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    elogind \
    jq \
    kmod \
    xterm \
    wget \
    va-driver-all \
    steam-installer && \
  ln -sf /usr/games/steam /usr/bin/steam && \
  echo "**** install Sunshine ****" && \
  SUNSHINE_RELEASE=$(curl -sX GET "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" | jq -r '.tag_name') && \
  SUNSHINE_URL=$(curl -sX GET "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" | jq -r '.assets[] | select(.name | contains("sunshine-debian-trixie-amd64.deb")) | .browser_download_url') && \
  echo "Downloading Sunshine ${SUNSHINE_RELEASE} from ${SUNSHINE_URL}" && \
  wget -O /tmp/sunshine.deb "${SUNSHINE_URL}" && \
  apt-get install -y /tmp/sunshine.deb && \
  echo "**** cleanup ****" && \
  printf "Build-date: ${BUILD_DATE}\nVersion: ${VERSION}" > /build_version && \
  apt-get clean && \
  rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

# add local files
COPY /root /

RUN chmod +x \
  /usr/local/bin/elogind-wrapper \
  /usr/local/bin/selkies-smoke-test \
  /usr/local/bin/steam-selkies \
  /etc/cont-init.d/45-selkies-wayland-socket-index.sh \
  /etc/cont-init.d/99-steam-selkies-autostart-migrate.sh

# ports and volumes
EXPOSE 3001 \
  47984/tcp \
  47989/tcp \
  48010/tcp \
  47998/udp \
  47999/udp \
  48000/udp
VOLUME /config
