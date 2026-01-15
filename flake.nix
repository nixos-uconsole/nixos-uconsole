{
  description = "NixOS for ClockworkPi uConsole";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # nvmd's nixos-raspberrypi provides Raspberry Pi support for NixOS
    # Handles bootloader, kernel, device trees, etc.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
    nixos-raspberrypi.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-raspberrypi,
      ...
    }@inputs:
    let
      # Helper function to create uConsole SD image configurations
      # Takes a variant (cm4 or cm5) and additional modules as arguments
      mkUConsoleImage =
        {
          variant ? "cm4",
          modules ? [ ],
        }:
        let
          # Select the appropriate nixos-raspberrypi modules based on variant
          rpiModules =
            if variant == "cm5" then
              [ nixos-raspberrypi.nixosModules.raspberry-pi-5.base ]
            else
              [
                nixos-raspberrypi.nixosModules.raspberry-pi-4.base
                nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
              ];
        in
        nixos-raspberrypi.lib.nixosSystem {
          # specialArgs makes these values available to all modules
          # Left side = attribute name modules will use
          # Right side = the actual value
          specialArgs = {
            inherit inputs; # Same as: inputs = inputs;
            nixos-raspberrypi = nixos-raspberrypi; # Lets modules access rpi-specific stuff
          };

          # `++` concatenates lists: [1 2] ++ [3 4] = [1 2 3 4]
          # We combine our base modules with any custom modules passed in
          modules = [
            #
            # === NixOS Base Modules ===
            # These come from nixpkgs and provide core functionality
            #
            "${nixpkgs}/nixos/modules/profiles/base.nix"
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"
            "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
          ]
          #
          # === Raspberry Pi Hardware Support ===
          # CM4 uses Pi 4 modules, CM5 uses Pi 5 modules
          #
          ++ rpiModules
          ++ [
            #
            # === uConsole-Specific Modules ===
            # Our custom modules for the ClockworkPi uConsole hardware
            #
            self.nixosModules.kernel # Kernel patches for display, power, etc.
            self.nixosModules.configtxt # Raspberry Pi boot configuration
            self.nixosModules.cm # Compute module kernel parameters and cache
            self.nixosModules.base # Good defaults (NetworkManager, SSH, etc.)
            self.nixosModules.uc-sleep # Power button sleep/wake handling
            self.nixosModules.uc-4g # Optional 4G module (enable with hardware.uc-4g.enable)

            #
            # === Compatibility Fixes ===
            # Required workarounds for nixos-raspberrypi integration
            #
            (
              {
                lib,
                modulesPath,
                config,
                pkgs,
                ...
              }:
              {
                # WHY: nixpkgs' rename.nix conflicts with nixos-raspberrypi's option names
                # This disables the problematic module
                disabledModules = [ (modulesPath + "/rename.nix") ];

                # WHY: Some modules use deprecated option paths like `environment.checkConfigurationOptions`
                # This creates an alias so old code still works
                imports = [
                  (lib.mkAliasOptionModule [ "environment" "checkConfigurationOptions" ] [ "_module" "check" ])
                ];

                # Tell Nix we're building for ARM64
                nixpkgs.hostPlatform = "aarch64-linux";

                # Use the "kernel" bootloader (direct kernel boot, not u-boot)
                boot.loader.raspberryPi.bootloader = "kernel";

                #
                # === Filesystem Configuration ===
                # Mount the firmware partition so nixos-rebuild can update boot files
                #
                fileSystems."/" = {
                  device = "/dev/disk/by-label/NIXOS_SD";
                  fsType = "ext4";
                };

                # Override nixpkgs sd-image.nix which hardcodes noauto/nofail
                # We need automount for nixos-raspberrypi's generational bootloader
                fileSystems."/boot/firmware" = {
                  device = "/dev/disk/by-label/FIRMWARE";
                  fsType = "vfat";
                  options = lib.mkForce [
                    "fmask=0022"
                    "dmask=0022"
                  ];
                };

                #
                # === SD Image Configuration ===
                # These settings control how the bootable SD image is created
                #

                # Image name includes variant: nixos-uconsole-cm4.img or nixos-uconsole-cm5.img
                # mkOverride 40 = priority 40 (lower = higher priority)
                # This beats mkForce (50) in case nixos-raspberrypi sets its own name
                image.baseName = lib.mkOverride 40 "nixos-uconsole-${variant}";

                sdImage = {
                  # Boot partition size in MB (holds kernel, DTBs, firmware)
                  firmwareSize = 1024;

                  # Partition ID (arbitrary, but consistent)
                  firmwarePartitionID = "0x2175794e";

                  # Don't compress - faster to flash, easier to resize
                  compressImage = false;

                  # These hooks run during image creation:

                  # Populate the boot/firmware partition with kernel, device trees, config.txt
                  # The firmwarePopulateCmd comes from nixos-raspberrypi's bootloader module
                  populateFirmwareCommands = ''
                    ${config.boot.loader.raspberryPi.firmwarePopulateCmd} \
                      -c ${config.system.build.toplevel} \
                      -f ./firmware
                  '';

                  # Populate the root filesystem
                  # Creates /boot/firmware mount point and installs boot files
                  populateRootCommands = ''
                    mkdir -p ./files/boot/firmware
                    ${config.boot.loader.raspberryPi.bootPopulateCmd} \
                      -c ${config.system.build.toplevel} \
                      -b ./files/boot
                  '';
                };

                system.stateVersion = "25.11";
              }
            )
          ]
          ++ modules; # Append any custom modules passed to mkUConsoleImage
        };

      # Helper function for users to create their own uConsole configurations
      # Usage: nixos-uconsole.lib.mkUConsoleSystem { variant = "cm4"; modules = [ ./configuration.nix ]; }
      mkUConsoleSystem =
        {
          variant ? "cm4",
          modules ? [ ],
          specialArgs ? { },
        }:
        let
          # Select the appropriate nixos-raspberrypi modules based on variant
          rpiModules =
            if variant == "cm5" then
              [ nixos-raspberrypi.nixosModules.raspberry-pi-5.base ]
            else
              [
                nixos-raspberrypi.nixosModules.raspberry-pi-4.base
                nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
              ];
        in
        nixos-raspberrypi.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            nixos-raspberrypi = nixos-raspberrypi;
          }
          // specialArgs;
          modules = rpiModules ++ [
            # uConsole hardware support
            self.nixosModules.kernel
            self.nixosModules.configtxt
            self.nixosModules.cm
            self.nixosModules.uc-sleep
            self.nixosModules.uc-4g

            # Compatibility fixes
            (
              { lib, modulesPath, ... }:
              {
                disabledModules = [ (modulesPath + "/rename.nix") ];
                imports = [
                  (lib.mkAliasOptionModule [ "environment" "checkConfigurationOptions" ] [ "_module" "check" ])
                ];
                nixpkgs.hostPlatform = "aarch64-linux";
                boot.loader.raspberryPi.bootloader = "kernel";

                # Filesystem configuration for SD card
                fileSystems."/" = lib.mkDefault {
                  device = "/dev/disk/by-label/NIXOS_SD";
                  fsType = "ext4";
                };

                # Override nixpkgs sd-image.nix which hardcodes noauto/nofail
                # We need automount for nixos-raspberrypi's generational bootloader
                fileSystems."/boot/firmware" = {
                  device = lib.mkDefault "/dev/disk/by-label/FIRMWARE";
                  fsType = lib.mkDefault "vfat";
                  options = lib.mkForce [
                    "fmask=0022"
                    "dmask=0022"
                  ];
                };
              }
            )
          ]
          ++ modules;
        };

    in
    {
      # Export mkUConsoleSystem for users
      lib = { inherit mkUConsoleSystem; };

      #
      # === Modules ===
      # These can be imported into your own NixOS configuration
      # Example: imports = [ inputs.nixos-uconsole.nixosModules.uconsole-cm4 ];
      #
      nixosModules = {
        kernel = import ./modules/kernel.nix;
        configtxt = import ./modules/configtxt.nix;
        cm = import ./modules/cm.nix;
        base = import ./modules/base.nix;
        uc-sleep = import ./modules/uc-sleep.nix;
        uc-4g = import ./modules/uc-4g.nix;

        # All-in-one: imports all uConsole modules (use with appropriate rpi base)
        uconsole-cm4 =
          { ... }:
          {
            imports = [
              self.nixosModules.kernel
              self.nixosModules.configtxt
              self.nixosModules.cm
              self.nixosModules.base
              self.nixosModules.uc-sleep
            ];
          };

        uconsole-cm5 =
          { ... }:
          {
            imports = [
              self.nixosModules.kernel
              self.nixosModules.configtxt
              self.nixosModules.cm
              self.nixosModules.base
              self.nixosModules.uc-sleep
            ];
          };
      };

      #
      # === Dev Shell ===
      # Enter with: nix develop (or direnv allow)
      #
      devShells =
        let
          mkDevShell =
            system:
            nixpkgs.legacyPackages.${system}.mkShell {
              packages = with nixpkgs.legacyPackages.${system}; [
                cachix
                gh
                zstd
                # Dev tools
                nixd # Nix LSP
                nixfmt # Nix formatter
                nixfmt-tree # Nix formatter for full repo formatting
                bash-language-server # Bash LSP
                shellcheck # Bash linter
                go-task # Task, kinda like `Make`
              ];
            };
        in
        {
          aarch64-linux.default = mkDevShell "aarch64-linux";
          x86_64-linux.default = mkDevShell "x86_64-linux";
        };

      #
      # === Pre-built Images ===
      # Build with: nix build .#minimal-cm4 or nix build .#minimal-cm5
      #
      packages.aarch64-linux = {
        minimal-cm4 =
          (mkUConsoleImage {
            variant = "cm4";
            modules = [ ./images/minimal.nix ];
          }).config.system.build.sdImage;

        minimal-cm5 =
          (mkUConsoleImage {
            variant = "cm5";
            modules = [ ./images/minimal.nix ];
          }).config.system.build.sdImage;
      };

      #
      # === NixOS Configurations ===
      # For evaluation/building: nix build .#nixosConfigurations.uconsole-cm4-minimal.config.system.build.toplevel
      #
      nixosConfigurations = {
        uconsole-cm4-minimal = mkUConsoleImage {
          variant = "cm4";
          modules = [ ./images/minimal.nix ];
        };

        uconsole-cm5-minimal = mkUConsoleImage {
          variant = "cm5";
          modules = [ ./images/minimal.nix ];
        };
      };
    };
}
