{ pkgs ? import <nixpkgs> { } }:

with pkgs;
let
  frameworks = darwin.apple_sdk.frameworks;
  # We don't need GLFW3 here when using Nim's staticglfw library.
  basePackages = [ dash freetype nim ];
  darwinPackages = [ frameworks.Cocoa frameworks.Kernel ];
  linuxPackages = [
    libGL
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXinerama
    xorg.xinput
    xorg.libXi
    xorg.libXext
    xorg.libXxf86vm
  ];
in mkShell {
  buildInputs = basePackages ++ lib.optionals hostPlatform.isLinux linuxPackages
    ++ lib.optionals hostPlatform.isDarwin darwinPackages;
}
