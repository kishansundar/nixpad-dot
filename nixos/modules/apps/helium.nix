{ pkgs, ... }:

# Helium, a Chromium-based browser, packaged from its official build.
let
  helium = pkgs.callPackage (
    {
      lib,
      stdenv,
      fetchurl,
      autoPatchelfHook,
      makeWrapper,
      wrapGAppsHook3,
      alsa-lib,
      at-spi2-atk,
      at-spi2-core,
      cairo,
      cups,
      dbus,
      expat,
      glib,
      gtk3,
      libdrm,
      libgbm,
      libGL,
      libpulseaudio,
      libva,
      libx11,
      libxcb,
      libxcomposite,
      libxdamage,
      libxext,
      libxfixes,
      libxkbcommon,
      libxrandr,
      nspr,
      nss,
      pango,
      pipewire,
      systemd,
      vulkan-loader,
      wayland,
    }:

    stdenv.mkDerivation (finalAttrs: {
      pname = "helium";
      version = "0.19.4.1";

      # Official build; ../../update-browsers.sh writes the newest version and hash.
      src = fetchurl {
        url = "https://github.com/imputnet/helium-linux/releases/download/${finalAttrs.version}/helium-${finalAttrs.version}-x86_64_linux.tar.xz";
        hash = "sha256-bKbkoA/vWRaCH7GvipYHzGs4b2eKfrQi5V8ZEWujBGk=";
      };

      nativeBuildInputs = [
        autoPatchelfHook
        makeWrapper
        wrapGAppsHook3
      ];

      # Libraries the binaries link against.
      buildInputs = [
        alsa-lib
        at-spi2-atk
        at-spi2-core
        cairo
        cups
        dbus
        expat
        glib
        gtk3
        libdrm
        libgbm
        libx11
        libxcb
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxkbcommon
        libxrandr
        nspr
        nss
        pango
        systemd
      ];

      # The launcher below is the only wrapper; it takes the GTK settings of wrapGAppsHook3.
      dontWrapGApps = true;

      installPhase = ''
        runHook preInstall

        mkdir -p $out/opt/helium
        cp -r * $out/opt/helium
        # Qt is not used, and the launcher of the build is replaced by the one below.
        rm $out/opt/helium/libqt5_shim.so $out/opt/helium/libqt6_shim.so $out/opt/helium/helium-wrapper

        install -Dm644 helium.desktop $out/share/applications/helium.desktop
        install -Dm644 product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png

        runHook postInstall
      '';

      # Run-time libraries autoPatchelf can't detect: graphics, video, sound, screen sharing.
      preFixup = ''
        makeWrapper $out/opt/helium/helium $out/bin/helium \
          "''${gappsWrapperArgs[@]}" \
          --set CHROME_VERSION_EXTRA nixos \
          --prefix LD_LIBRARY_PATH : ${
            lib.makeLibraryPath [
              libGL
              libpulseaudio
              libva
              pipewire
              vulkan-loader
              wayland
            ]
          }
      '';

      meta = {
        description = "Helium, a private Chromium-based browser";
        homepage = "https://helium.computer";
        license = lib.licenses.gpl3Only;
        platforms = [ "x86_64-linux" ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        mainProgram = "helium";
      };
    })
  ) { };
in
{
  environment.systemPackages = [ helium ];
}
