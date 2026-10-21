{ pkgs, ... }:

# Zen Browser, packaged here from its official build (it is not in nixpkgs).
let
  zen = pkgs.callPackage (
    {
      lib,
      stdenv,
      fetchurl,
      wrapFirefox,
      writeText,
      autoPatchelfHook,
      patchelfUnstable,
      wrapGAppsHook3,
      adwaita-icon-theme,
      alsa-lib,
      curl,
      dbus-glib,
      gtk3,
      libva,
      libxtst,
      pciutils,
      pipewire,
    }:

    let
      version = "1.23.3b";

      # Zen's own updater can't work in the Nix store; change version and hash to update.
      policiesJson = writeText "zen-policies.json" (
        builtins.toJSON { policies.DisableAppUpdate = true; }
      );

      # Same recipe as firefox-bin in nixpkgs: unpack the official build and patch its binaries.
      unwrapped = stdenv.mkDerivation {
        pname = "zen-unwrapped";
        inherit version;

        # Official build; ../../update-packages.sh writes the newest version and hash.
        src = fetchurl {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-x86_64.tar.xz";
          hash = "sha256-uyBF0+IWVNQP6EElAJLurf0sH8gx7vtQkiJ3PIvcoUk=";
        };

        nativeBuildInputs = [
          autoPatchelfHook
          patchelfUnstable
          wrapGAppsHook3
        ];

        # Libraries the binaries link against.
        buildInputs = [
          adwaita-icon-theme
          alsa-lib
          dbus-glib
          gtk3
          libxtst
        ];

        # Libraries loaded at run time, which autoPatchelf can't detect by itself.
        runtimeDependencies = [
          curl
          libva.out
          pciutils
        ];
        appendRunpaths = [ "${pipewire}/lib" ];

        # Firefox-based builds process relocations from a fixed offset.
        patchelfFlags = [ "--no-clobber-old-sections" ];

        installPhase = ''
          runHook preInstall

          mkdir -p $out/lib/zen-bin-${version}
          cp -r * $out/lib/zen-bin-${version}

          mkdir -p $out/bin
          ln -s $out/lib/zen-bin-${version}/zen $out/bin/zen

          mkdir -p $out/lib/zen-bin-${version}/distribution
          ln -s ${policiesJson} $out/lib/zen-bin-${version}/distribution/policies.json

          runHook postInstall
        '';

        # What wrapFirefox needs to know about this browser.
        passthru = {
          applicationName = "Zen Browser";
          binaryName = "zen";
          libName = "zen-bin-${version}";
          withFFmpeg = true;
          gssSupport = true;
          inherit gtk3;
        };

        meta = {
          description = "Zen Browser, a Firefox-based browser";
          homepage = "https://zen-browser.app";
          license = lib.licenses.mpl20;
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
          mainProgram = "zen";
        };
      };
    in
    # Adds launcher, icons and media libraries; the wrapper is shown the Gecko version (158, MaxVersion in the build's application.ini; check it at each Zen update).
    wrapFirefox (unwrapped // { version = "158.0"; }) { inherit version; }
  ) { };
in
{
  environment.systemPackages = [ zen ];
}
