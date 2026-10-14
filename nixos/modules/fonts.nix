{ pkgs, ... }:

# Fonts: which are installed, and which each kind of text uses by default.
let
  # Libron serif font, packaged from github.com/nicoverbruggen/libron (not in nixpkgs); ../update-browsers.sh writes the newest version and hash.
  libron = pkgs.callPackage (
    {
      lib,
      stdenvNoCC,
      fetchzip,
    }:

    stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "libron";
      version = "0.31";

      src = fetchzip {
        url = "https://github.com/nicoverbruggen/libron/releases/download/v${finalAttrs.version}/Libron.zip";
        hash = "sha256-UD+8cjdiomyEtGlLtkmcNd8Y8wNU8RIEwyPdq55nm4o=";
        stripRoot = false;
      };

      installPhase = ''
        runHook preInstall
        install -Dm644 -t $out/share/fonts/truetype *.ttf
        runHook postInstall
      '';

      meta = {
        description = "Serif font tuned for digital reading, a revision of Readerly";
        homepage = "https://github.com/nicoverbruggen/libron";
        license = lib.licenses.ofl;
        platforms = lib.platforms.all;
      };
    })
  ) { };
in
{
  # A basic set covering most languages and emoji, so no text shows as empty boxes.
  fonts.enableDefaultPackages = true;

  # Fonts must be listed here, not in systemPackages, for fontconfig to see them.
  fonts.packages = [
    # Terminal, code, and the bar and its panels; the Nerd Font build adds icon glyphs.
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.symbols-only
    # Last-resort symbol font for Emacs (not open source; allowed by name in configuration.nix).
    pkgs.symbola

    # Text in app windows and menus. Only the Sans family of IBM Plex.
    (pkgs.ibm-plex.override { families = [ "sans" ]; })

    # Reading text. Packaged above.
    libron
  ];

  # What an app gets when it asks for "serif", "sans-serif" or "monospace".
  fonts.fontconfig.defaultFonts = {
    serif = [ "Libron" ];
    sansSerif = [ "IBM Plex Sans" ];
    monospace = [ "JetBrainsMono Nerd Font" ];
  };
}
