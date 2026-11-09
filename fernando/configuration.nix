# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

let
  # Keep Flameshot on v13 even when the system channel moves to newer releases.
  flameshot13 = pkgs.flameshot.overrideAttrs (_: {
    version = "13.3.0";
    src = pkgs.fetchFromGitHub {
      owner = "flameshot-org";
      repo = "flameshot";
      tag = "v13.3.0";
      hash = "sha256-RyoLniRmJRinLUwgmaA4RprYAVHnoPxCP9LyhHfUPe0=";
    };
    # Match the v13 packaging patches instead of inheriting v14's CMake changes.
    patches = map (patch: pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41/pkgs/by-name/fl/flameshot/${patch.name}";
      inherit (patch) sha256;
    }) [
      {
        name = "load-missing-deps.patch";
        sha256 = "1k7ncp618w0v1ck5gn5vmpmpb4bblr3d3byhbsxc83cix2haxfsx";
      }
      {
        name = "macos-build.patch";
        sha256 = "0n2lhhxgnhpgsxjk516h55alfb68dsv212s41s06ajf4czc2lm2m";
      }
    ];
  });
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./vms.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 3;

  networking.hostName = "fernando"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

  # Set your time zone.
  time.timeZone = "America/Sao_Paulo";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.eduardo = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree
    ];
  };

  programs.zsh = {
    enable = true;
    shellAliases.cat = "bat --plain --paging=never";
    ohMyZsh = {
      enable = true;
      theme = "agnoster";
      plugins = [ "git" ];
    };
  };
  programs.git.enable = true;
  environment.variables.EDITOR = "nano";
  environment.variables.TERMINAL = "alacritty";

  fonts.packages = with pkgs; [ nerd-fonts.dejavu-sans-mono fira-code ];
  # Include the Powerline glyphs used by the Agnoster prompt.
  fonts.fontconfig.defaultFonts.monospace = [ "DejaVuSansM Nerd Font Mono" ];

  # Unlock the login keyring when logging into the console before starting Sway.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  # Keep SSH keys in OpenSSH's agent, loaded manually with ssh-add.
  services.gnome.gcr-ssh-agent.enable = false;
  programs.ssh.startAgent = true;

  programs.sway.enable = true;
  programs.sway.extraSessionCommands = ''
    ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets >/dev/null
  '';
  # Match i3: Brazilian and US layouts, switched with Super+Space.
  environment.etc."sway/config.d/keyboard.conf".text = ''
    input type:keyboard {
      xkb_layout br,us
      xkb_options grp:win_space_toggle
    }
  '';
  environment.etc."sway/config.d/desktop.conf".text = ''
    set $term alacritty
    bindsym $mod+Return exec $term
    exec dbus-update-activation-environment --systemd SSH_AUTH_SOCK
    bindsym Print exec env QT_QPA_PLATFORM=wayland ${flameshot13}/bin/flameshot gui
    for_window [app_id="flameshot"] border pixel 0, floating enable, fullscreen disable, move absolute position 0 0
  '';
  programs.firefox.enable = true;
  programs.obs-studio.enable = true;
  environment.systemPackages = [ pkgs.nano pkgs.bat pkgs.alacritty pkgs.seahorse flameshot13 ];
  environment.etc."alacritty/alacritty.toml".source = (pkgs.formats.toml {}).generate "alacritty.toml" {
    font.normal.family = "DejaVuSansM Nerd Font Mono";
    # Foot 1.28's default dark palette.
    colors = {
      primary = { background = "#242424"; foreground = "#ffffff"; };
      normal = {
        black = "#242424"; red = "#f62b5a"; green = "#47b413"; yellow = "#e3c401";
        blue = "#24acd4"; magenta = "#f2affd"; cyan = "#13c299"; white = "#e6e6e6";
      };
      bright = {
        black = "#616161"; red = "#ff4d51"; green = "#35d450"; yellow = "#e9e836";
        blue = "#5dc5f8"; magenta = "#feabf2"; cyan = "#24dfc4"; white = "#ffffff";
      };
    };
  };

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = true;

  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?
}
