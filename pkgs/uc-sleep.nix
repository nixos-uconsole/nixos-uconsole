{
  lib,
  python3Packages,
  fetchFromGitHub,
  ...
}:
python3Packages.buildPythonApplication {
  pname = "uc-sleep";
  version = "0-unstable-20251215";
  format = "other";

  src = fetchFromGitHub {
    owner = "robertjakub";
    repo = "uConsole-sleep";
    rev = "fb97421766eea93f55ac31d1865c47e0913cee70";
    hash = "sha256-zJzKKENLPsgun7zGSpNLy6LPcdO55F/XeLDbAxxZpD0=";
  };

  dependencies = with python3Packages; [
    python-uinput
    inotify-simple
  ];

  nativeBuildInputs = [
    python3Packages.pyinstaller
  ];

  buildPhase = ''
    runHook preBuild
    cd src
    pyinstaller --clean --noconfirm --hidden-import=_libsuinput -F --distpath . sleep_power_control.py
    pyinstaller --clean --noconfirm --hidden-import=_libsuinput -F --distpath . sleep_remap_powerkey.py
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m 0555 sleep_power_control $out/bin
    install -m 0555 sleep_remap_powerkey $out/bin
    runHook postInstall
  '';

  meta = {
    description = "uConsole power button sleep/wake handling";
    homepage = "https://github.com/robertjakub/uConsole-sleep";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
