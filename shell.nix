# The host speaks ramen's sockets; Processing draws. Built by ./build.sh.
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  nativeBuildInputs = [ pkgs.ldc pkgs.dub ];
}
