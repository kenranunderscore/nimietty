{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.dash
    pkgs.libGL
    pkgs.freetype
    # FIXME this obviously doesn't work on macOS
    pkgs.xorg.libXcursor
    pkgs.xorg.libXrandr
    pkgs.xorg.libXinerama
    pkgs.xorg.xinput
    pkgs.xorg.libXi
    pkgs.xorg.libXext
    pkgs.xorg.libXxf86vm
  ];
}
