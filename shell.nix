{
  pkgs ? import <nixpkgs> {},
  unstable ? import <nixos-unstable> {},
}:
# - [Failed to initialize any backend! · emilk/egui · Discussion #1587 · GitHub](https://github.com/emilk/egui/discussions/1587)
pkgs.stdenv.mkDerivation rec {
  name = "rust";
  buildInputs = with pkgs; [
    libxkbcommon
    libGL

    # WINIT_UNIX_BACKEND=wayland
    wayland

    # - [No appropiate adapter found](https://github.com/gfx-rs/wgpu/issues/3033)
    # WINIT_UNIX_BACKEND=x11
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXi
    xorg.libX11

    # WGPU_BACKEND=vulkan
    glslang
    vulkan-headers
    vulkan-loader
    vulkan-validation-layers

    # tools
    # glxinfo # glxinfo
    # wgpu-utils # wgpuinfo
    # vulkan-tools # vulkaninfo
  ];
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath buildInputs}";
  # shellHook = ''
  #     export OPENSSL_DIR="${openssl.dev}"
  #     export OPENSSL_LIB_DIR="${openssl.out}/lib"
  # '';
}
