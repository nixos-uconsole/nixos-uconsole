{
  lib,
  buildGoModule,
  ...
}:

buildGoModule {
  pname = "uc-power";
  version = "0.2.0";

  src = ./uc-power;

  vendorHash = "sha256-hj1rQJED2llW782lPYYWDD1TgNgHPa0z9nUdj4kWryw=";

  ldflags = [
    "-s"
    "-w"
  ];

  subPackages = [
    "cmd/uc-power-button"
    "cmd/uc-display-power"
  ];

  meta = {
    description = "uConsole power management utilities";
    homepage = "https://github.com/nixos-uconsole/nixos-uconsole";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
