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
        { device = "/dev/mapper/nix_root";
          fsType = "btrfs";
          options = [ "compress=zstd:1" ];
        };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/ED2B-9062";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };

      boot.initrd.luks.devices."nix_root".device = "/dev/disk/by-uuid/22f0b874-3d61-4270-9baf-2ec304ecf2e8";

      # Resume from the NixOS NVMe swap partition in every boot profile.
      boot.resumeDevice = "/dev/disk/by-uuid/3c0b1ed4-97a6-45b3-b2e0-6d5732017c94";

      swapDevices =
        [ { device = "/dev/disk/by-uuid/3c0b1ed4-97a6-45b3-b2e0-6d5732017c94"; }
        ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      specialisation.standard.configuration.hardware.fernando.kernelProfile = "standard";
      specialisation.realtime-reserved.configuration.hardware.fernando.kernelProfile = "realtime-reserved";
    }
  ]);
}
