{
  lib,
  python3,
  fetchFromGitHub,
  ...
}:
let
  python = python3.withPackages (ps: [
    ps.python-uinput
    ps.inotify-simple
  ]);
in
python3.pkgs.buildPythonApplication {
  pname = "uc-sleep";
  version = "0-unstable-20251215";
  format = "other";

  src = fetchFromGitHub {
    owner = "robertjakub";
    repo = "uConsole-sleep";
    rev = "fb97421766eea93f55ac31d1865c47e0913cee70";
    hash = "sha256-zJzKKENLPsgun7zGSpNLy6LPcdO55F/XeLDbAxxZpD0=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    echo "#!${python}/bin/python3" > $out/bin/sleep_power_control
    cat src/sleep_power_control.py >> $out/bin/sleep_power_control
    chmod 0555 $out/bin/sleep_power_control

    echo "#!${python}/bin/python3" > $out/bin/sleep_remap_powerkey
    cat src/sleep_remap_powerkey.py >> $out/bin/sleep_remap_powerkey
    chmod 0555 $out/bin/sleep_remap_powerkey
    runHook postInstall
  '';

  meta = {
    description = "uConsole power button sleep/wake handling";
    homepage = "https://github.com/robertjakub/uConsole-sleep";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
