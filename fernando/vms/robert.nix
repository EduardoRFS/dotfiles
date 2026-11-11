{ lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.hostName = "robert";
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";
  system.stateVersion = "26.05";

  # Use the EFI fallback path; installation from the host must not change its NVRAM.
  boot.loader.systemd-boot.enable = true;
  boot.kernelParams = [ "console=ttyS0,115200" ];
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/4B68-2296";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };
  swapDevices = [ { device = "/dev/disk/by-uuid/03ed5865-d18b-4169-9345-071db63e9049"; } ];
  # TODO: Encrypt Robert's root filesystem; it is plain Btrfs for now.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/c7776b8c-84f6-4e02-8c87-3ef5dd73eb34";
    fsType = "btrfs";
  };

  services.qemuGuest.enable = true;
  services.avahi = {
    enable = true;
    settings.publish = {
      disable-publishing = false;
      publish-addresses = true;
    };
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "eduardo" ];
    };
  };
  users.users.eduardo = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzASc8q0XvdE7de3eSvktU3DiVkz2xwxMY/qZTzhZ4Z"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    interactiveShellInit = lib.mkAfter ''
      prompt_context() {}
      source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
    '';
    shellAliases.cat = "bat --plain --paging=never";
    ohMyZsh = {
      enable = true;
      theme = "agnoster";
      plugins = [ "git" ];
    };
  };
  programs.git.enable = true;
  programs.direnv.enable = true;
  environment.variables.EDITOR = "nano";
  environment.systemPackages = with pkgs; [ nano bat tree zsh-completions zstd ];
}
