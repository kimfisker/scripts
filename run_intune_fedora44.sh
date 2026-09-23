#!/usr/bin/env bash

env \
  LIBGL_ALWAYS_SOFTWARE=1 \
  WEBKIT_DISABLE_COMPOSITING_MODE=1 \
  WEBKIT_FORCE_SANDBOX=0 \
  LD_PRELOAD="/usr/lib64/libssl.so.3:/usr/lib64/libcrypto.so.3:/usr/lib/libcrypto-332.so:/usr/lib/libssl-332.so" \
  DISPLAY="${DISPLAY:-:0}" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_RUNTIME_DIR="/run/user/$(id -u)" \
  /opt/microsoft/intune/bin/intune-portal
