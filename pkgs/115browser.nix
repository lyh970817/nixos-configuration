{
  lib,
  fetchurl,
  runCommand,
  dpkg,
  gcc,
  buildFHSEnv,
  writeScript,
  writeShellScriptBin,
}:

let
  pname = "115browser";
  version = "36.0.0";

  src = fetchurl {
    url = "https://down.115.com/client/115pc/lin/115br_v${version}.deb";
    sha256 = "0j7wnihmd1i6vaczzi6kf6g8f4lbpp95lziig7hz2j3zdpiv97qk";
  };

  browserSrc = runCommand "115browser-source" { nativeBuildInputs = [ dpkg ]; } ''
    mkdir -p $out
    dpkg-deb -x ${src} $out
  '';

  diskSpaceHack = runCommand "115browser-libdiskfake" { nativeBuildInputs = [ gcc ]; } ''
    mkdir -p $out/lib
    cat > hack.c <<'EOF'
    #define _GNU_SOURCE
    #include <sys/statvfs.h>
    #include <sys/vfs.h>
    #include <dlfcn.h>
    #include <sys/types.h>
    #include <stdio.h>
    #include <string.h>

    typedef int (*statvfs_fn)(const char *path, struct statvfs *buf);
    typedef int (*statvfs64_fn)(const char *path, struct statvfs64 *buf);
    typedef int (*statfs_fn)(const char *path, struct statfs *buf);
    typedef int (*statfs64_fn)(const char *path, struct statfs64 *buf);

    const unsigned long long FAKE_SIZE = 1099511627776ULL;

    int statvfs(const char *path, struct statvfs *buf) {
        statvfs_fn original = (statvfs_fn)dlsym(RTLD_NEXT, "statvfs");
        int res = original(path, buf);
        if (res == 0) {
            unsigned long long blocks = FAKE_SIZE / buf->f_frsize;
            buf->f_blocks = blocks;
            buf->f_bfree = blocks;
            buf->f_bavail = blocks;
        }
        return res;
    }

    int statvfs64(const char *path, struct statvfs64 *buf) {
        statvfs64_fn original = (statvfs64_fn)dlsym(RTLD_NEXT, "statvfs64");
        int res = original(path, buf);
        if (res == 0) {
            unsigned long long blocks = FAKE_SIZE / buf->f_frsize;
            buf->f_blocks = blocks;
            buf->f_bfree = blocks;
            buf->f_bavail = blocks;
        }
        return res;
    }

    int statfs(const char *path, struct statfs *buf) {
        statfs_fn original = (statfs_fn)dlsym(RTLD_NEXT, "statfs");
        int res = original(path, buf);
        if (res != 0) {
             buf->f_type = 0xEF53;
             buf->f_bsize = 4096;
             buf->f_frsize = 4096;
             res = 0;
        }

        if (res == 0) {
            unsigned long long blocks = FAKE_SIZE / buf->f_bsize;
            buf->f_blocks = blocks;
            buf->f_bfree = blocks;
            buf->f_bavail = blocks;
        }
        return res;
    }

    int statfs64(const char *path, struct statfs64 *buf) {
        statfs64_fn original = (statfs64_fn)dlsym(RTLD_NEXT, "statfs64");
        int res = original(path, buf);
        if (res != 0) {
             buf->f_type = 0xEF53;
             buf->f_bsize = 4096;
             buf->f_frsize = 4096;
             res = 0;
        }

        if (res == 0) {
            unsigned long long blocks = FAKE_SIZE / buf->f_bsize;
            buf->f_blocks = blocks;
            buf->f_bfree = blocks;
            buf->f_bavail = blocks;
        }
        return res;
    }
    EOF

    gcc -shared -fPIC -ldl -O2 hack.c -o $out/lib/libdiskfake.so
  '';

  browserEnv = buildFHSEnv {
    name = "115browser-env";

    targetPkgs =
      pkgs: with pkgs; [
        mesa
        libgbm
        libGL
        libglvnd
        libdrm
        libxshmfence
        wayland
        udev
        coreutils
        util-linux
        xdg-utils
        glibcLocales
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
        source-han-sans
        source-han-serif
        wqy_zenhei
        wqy_microhei
        liberation_ttf
        alsa-lib
        at-spi2-atk
        at-spi2-core
        cairo
        cups
        curl
        dbus
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk3
        libxkbcommon
        nspr
        nss
        openssl
        pango
        xorg.libX11
        xorg.libXcomposite
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXrender
        xorg.libXScrnSaver
        xorg.libxcb
        xorg.libxshmfence
      ];

    extraBwrapArgs = [
      "--bind"
      "$HOME"
      "$HOME"
      "--bind"
      "$HOME/.cache/115browser-tmp"
      "/tmp"
      "--bind"
      "$HOME/.cache/115browser-tmp"
      "/var/tmp"
      "--ro-bind"
      "/tmp/.X11-unix"
      "/tmp/.X11-unix"
      "--dev-bind"
      "/dev"
      "/dev"
    ];

    profile = ''
      export XDG_DATA_DIRS=/usr/share:$XDG_DATA_DIRS
      export FONTCONFIG_FILE=/etc/fonts/fonts.conf
      export LC_ALL=C.UTF-8
      export XDG_DOWNLOAD_DIR="$HOME/Downloads"
    '';

    runScript = writeScript "init-115browser" ''
      #!/bin/bash
      RUN_DIR="$HOME/.cache/115browser-run"
      mkdir -p "$RUN_DIR"

      if [ -w /etc ]; then
        rm -f /etc/mtab
        ln -s /proc/mounts /etc/mtab
      fi

      if [ -d "${browserSrc}/usr/local/115Browser" ]; then
        SOURCE_DIR="${browserSrc}/usr/local/115Browser"
      elif [ -d "${browserSrc}/opt/115browser" ]; then
        SOURCE_DIR="${browserSrc}/opt/115browser"
      else
        echo "Error: Could not find 115Browser binary."
        exit 1
      fi

      cp -rf --no-preserve=mode,ownership "$SOURCE_DIR/"* "$RUN_DIR/"
      cd "$RUN_DIR"
      chmod -R u+wx .

      rm -f libEGL.so* libGLESv2.so* libvk_swiftshader.so* libvulkan.so* libgbm.so*
      if [ -e /usr/lib/libudev.so.1 ] && [ ! -e ./libudev.so.0 ]; then
        ln -sf /usr/lib/libudev.so.1 ./libudev.so.0
      fi

      export LD_LIBRARY_PATH=$PWD:/usr/lib:/lib:$LD_LIBRARY_PATH
      export GDK_SCALE=1
      export LD_PRELOAD=${diskSpaceHack}/lib/libdiskfake.so

      exec ./115Browser \
        --disable-setuid-sandbox \
        --force-device-scale-factor=1 \
        --disk-cache-dir="$RUN_DIR/cache" \
        --user-data-dir="$RUN_DIR/profile" \
        --no-default-browser-check \
        "$@"
    '';
  };
in
(writeShellScriptBin "115browser" ''
  mkdir -p "$HOME/.cache/115browser-tmp/.X11-unix"
  mkdir -p "$HOME/.cache/115browser-run"
  mkdir -p "$HOME/Downloads"
  mkdir -p "$HOME/115"

  ARGS=()
  ARGS+=(--bind "$HOME/.cache/115browser-tmp" "/tmp")
  ARGS+=(--bind "$HOME/.cache/115browser-tmp" "/var/tmp")
  ARGS+=(--ro-bind "/tmp/.X11-unix" "/tmp/.X11-unix")

  if [ -d "/dev/shm" ]; then ARGS+=(--bind "/dev/shm" "/dev/shm"); fi
  if [ -d "/mnt" ]; then ARGS+=(--bind "/mnt" "/mnt"); fi
  if [ -d "/run/media" ]; then ARGS+=(--bind "/run/media" "/run/media"); fi
  if [ -d "/media" ]; then ARGS+=(--bind "/media" "/media"); fi

  exec ${browserEnv}/bin/115browser-env --bwrap-flags "''${ARGS[*]}" "$@"
'').overrideAttrs
  (_old: {
    inherit pname version;

    meta = with lib; {
      description = "115 Browser desktop client";
      homepage = "https://115.com";
      license = licenses.unfree;
      mainProgram = "115browser";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  })
