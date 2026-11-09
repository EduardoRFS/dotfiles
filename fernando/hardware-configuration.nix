{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" ];
  # Reserve the integrated GPU and its audio device.
  boot.kernelParams = [ "vfio-pci.ids=1002:164e,1002:1640" ];
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
}
