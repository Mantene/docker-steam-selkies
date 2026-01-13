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
  echo "**** install Steam + KDE Plasma + Sunshine prereqs ****" && \
  dpkg --add-architecture i386 && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    elogind \
    jq \
    kmod \
    xauth \
    x11-utils \
    x11-xserver-utils \
    xterm \
    xwayland \
    wget \
    va-driver-all \
    steam-installer && \
  apt-get install -y --no-install-recommends \
    plasma-desktop \
    sddm \
    kde-plasma-desktop \
    konsole \
    dolphin \
    kwin-x11 \
    kde-config-gtk-style \
    kde-cli-tools \
    kde-spectacle \
    xinit \
    dbus-x11 \
    weston \
    kwin-wayland \
    plasma-workspace && \
  if [ -f /usr/bin/xterm ]; then chmod u-s /usr/bin/xterm || true; fi && \
  echo "**** ensure elogind daemon path ****" && \
  ELOGIND_DAEMON="" && \
  if dpkg -L elogind >/dev/null 2>&1; then \
    ELOGIND_DAEMON="$(dpkg -L elogind 2>/dev/null | awk '/\/elogind$/{print; exit}')"; \
  fi && \
  if [ -n "${ELOGIND_DAEMON}" ] && [ ! -x "${ELOGIND_DAEMON}" ]; then \
    ELOGIND_DAEMON=""; \
  fi && \
  if [ -z "${ELOGIND_DAEMON}" ]; then \
    for p in \
      /usr/lib/elogind/elogind \
      /lib/elogind/elogind \
      /usr/libexec/elogind/elogind \
      /libexec/elogind/elogind; do \
      if [ -x "${p}" ]; then ELOGIND_DAEMON="${p}"; break; fi; \
    done; \
  fi && \
  if [ -z "${ELOGIND_DAEMON}" ]; then \
    echo "ERROR: elogind daemon binary not found after install" >&2; \
    dpkg -L elogind || true; \
    exit 1; \
  fi && \
  mkdir -p /usr/lib/elogind && \
  ln -sf "${ELOGIND_DAEMON}" /usr/lib/elogind/elogind && \
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


# add local files (match linuxserver baseimage conventions)
# - /defaults/* are used by the window manager/session
# - /custom-cont-init.d/* run during container init
COPY root/defaults/ /defaults/
COPY root/usr/ /usr/
COPY root/etc/dbus-1/ /etc/dbus-1/
COPY root/etc/cont-init.d/ /custom-cont-init.d/

# set permissions
RUN chmod +x \
  /usr/local/bin/elogind-wrapper \
  /usr/local/bin/kwin_x11_replace \
  /usr/local/bin/org.freedesktop.login1 \
  /usr/local/bin/selkies-smoke-test \
  /usr/local/bin/steam-selkies \
  /custom-cont-init.d/10-tmp-x11-dirs.sh \
  /custom-cont-init.d/11-dbus-servicehelper-hardening.sh \
  /custom-cont-init.d/12-fix-config-ownership.sh \
  /custom-cont-init.d/13-fix-dri-permissions.sh \
  /custom-cont-init.d/14-fix-tmp-socket-dirs.sh \
  /custom-cont-init.d/44-start-elogind.sh \
  /custom-cont-init.d/45-selkies-wayland-socket-index.sh \
  /custom-cont-init.d/46-dbus-login1-override.sh \
  /custom-cont-init.d/47-dbus-servicehelper-permissions.sh \
  /custom-cont-init.d/48-start-upower-udisks2.sh \
  /custom-cont-init.d/99-steam-selkies-autostart-migrate.sh \
  /defaults/startwm_wayland.sh \
  /defaults/autostart

ENTRYPOINT ["/init"]

# ports and volumes
EXPOSE 3001 \
  47984/tcp \
  47989/tcp \
  48010/tcp \
  47998/udp \
  47999/udp \
  48000/udp
VOLUME /config
