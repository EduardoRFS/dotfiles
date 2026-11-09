{ config, lib, pkgs, modulesPath, ... }:

let
  vmCPUs = "12-15,28-31";
  hostCPUs = "0-11,16-27";
  hostAffinity = "0-11 16-27";

  kernels = {
    standard = pkgs.linuxPackages_6_18;
    realtime = pkgs.linuxPackagesFor (pkgs.linux_6_18.override {
      structuredExtraConfig = with lib.kernel; {
        EXPERT = yes;
        PREEMPT_RT = yes;
        # Intel GVT is unavailable with PREEMPT_RT.
        DRM_I915_GVT = lib.mkForce (option no);
        DRM_I915_GVT_KVMGT = lib.mkForce (option no);
      };
    });
  };

  profiles = {
    standard = { realtime = false; reserveCores = false; };
    realtime = { realtime = true; reserveCores = false; };
    realtime-reserved = { realtime = true; reserveCores = true; };
  };

  profileName = config.hardware.fernando.kernelProfile;

  mkProfile = name: { realtime, reserveCores }: lib.mkMerge [
    {
      boot.kernelPackages = if realtime then kernels.realtime else kernels.standard;
      # Tick suppression also offloads RCU callbacks, without reserving CPUs.
      boot.kernelParams = lib.optional realtime "nohz_full=${vmCPUs}";
      system.nixos.tags = [ name ];
    }
    (lib.mkIf reserveCores {
      # Domain isolation lasts until reboot; managed IRQ avoidance is best effort.
      boot.kernelParams = [
        "isolcpus=domain,managed_irq,${vmCPUs}"
        "irqaffinity=${hostCPUs}"
      ];
      # Keep host services and sessions off the VM cores. Pin VM vCPUs explicitly.
      systemd.settings.Manager.CPUAffinity = hostAffinity;
      systemd.slices.system.sliceConfig.AllowedCPUs = hostAffinity;
      systemd.slices.user.sliceConfig.AllowedCPUs = hostAffinity;
      services.irqbalance.enable = lib.mkForce false;
    })
  ];
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  options.hardware.fernando.kernelProfile = lib.mkOption {
    type = lib.types.enum (builtins.attrNames profiles);
    default = "realtime";
    description = "Kernel and CPU isolation profile for fernando.";
  };

  config = lib.mkMerge ((lib.mapAttrsToList
    (name: profile: lib.mkIf (profileName == name) (mkProfile name profile))
    profiles) ++ [
    {
      # Share these packages with the toy guest defined in vms.nix.
      _module.args.fernandoKernels = kernels;

      boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" ];
      boot.kernelParams = [
        # Reserve the integrated GPU and its audio device.
        "vfio-pci.ids=1002:164e,1002:1640"
      ];
      boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" =
        { device = "/dev/mapper/another_root";
          fsType = "btrfs";
        };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/F84D-72E9";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };

      boot.initrd.luks.devices."another_root".device = "/dev/disk/by-uuid/77a06efa-992f-44d5-b58b-dadcad5e1dde";

      swapDevices =
        [ { device = "/dev/disk/by-uuid/1584fff4-7d02-43e9-900e-c461d8b4bfb4"; }
        ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      specialisation.standard.configuration.hardware.fernando.kernelProfile = "standard";
      specialisation.realtime-reserved.configuration.hardware.fernando.kernelProfile = "realtime-reserved";
    }
  ]);
}
