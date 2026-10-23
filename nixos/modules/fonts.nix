{ pkgs, ... }:

# Fonts: which are installed, and which each kind of text uses by default.
let
  # Libron serif font, packaged from github.com/nicoverbruggen/libron (not in nixpkgs); ../update-packages.sh writes the newest version and hash.
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

  # The bar's running cat (Waycat, github.com/CarloCattano/waycat: RunCat's cat as a font); its repo states no licence, so it is fetched at a fixed commit and not kept in this repo.
  waycat = pkgs.runCommand "waycat-font" { } ''
    install -Dm644 ${pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/CarloCattano/waycat/423a59c29accc0f73cf0f35cf2f823081fa26184/fonts/Waycat.ttf";
      hash = "sha256-W7otvv+Dho/Nz9Jk6ehDZLhreH8/33Vc96AgCic/ZD8=";
    }} $out/share/fonts/truetype/Waycat.ttf
  '';
in
{
  # A basic set covering most languages and emoji, so no text shows as empty boxes.
  fonts.enableDefaultPackages = true;

  # Fonts must be listed here, not in systemPackages, for fontconfig to see them.
  fonts.packages = [
    # Terminal, code, and the bar and its panels; the Nerd Font build adds icon glyphs.
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.symbols-only

    # Text in app windows and menus. Only the Sans family of IBM Plex.
    (pkgs.ibm-plex.override { families = [ "sans" ]; })

    # Reading text. Packaged above.
    libron

    # The bar's running cat. Packaged above.
    waycat
  ];

  # What an app gets when it asks for "serif", "sans-serif" or "monospace".
  fonts.fontconfig.defaultFonts = {
    serif = [ "Libron" ];
    sansSerif = [ "IBM Plex Sans" ];
    monospace = [ "JetBrainsMono Nerd Font" ];
  };
}
