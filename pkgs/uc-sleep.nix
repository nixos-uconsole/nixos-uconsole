{
  lib,
  buildGoModule,
  ...
}:

buildGoModule {
  pname = "uc-sleep";
  version = "0.1.0";

  src = ./uc-sleep;

  vendorHash = null; # pure stdlib, no deps

  ldflags = [
    "-s"
    "-w"
  ];

  # Build both commands
  subPackages = [
    "cmd/uc-power-button"
    "cmd/uc-power-control"
  ];

  meta = {
    description = "uConsole power button sleep/wake handling";
    homepage = "https://github.com/nixos-uconsole/nixos-uconsole";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
