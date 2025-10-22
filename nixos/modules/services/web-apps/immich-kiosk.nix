{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.immich-kiosk;
  format = pkgs.formats.json { };
  configFile = "/run/immich-kiosk/config.yaml";
  configDir = builtins.dirOf configFile;
  settings = if cfg.settings == null then { } else cfg.settings;
  secretsReplacement = utils.genJqSecretsReplacement {
    loadCredential = true;
  } settings configFile;
  kioskPort = lib.attrByPath [ "kiosk" "port" ] 3000 settings;
  inherit (lib)
    types
    mkIf
    mkOption
    mkEnableOption
    mkPackageOption
    ;
in
{
  meta.maintainers = with lib.maintainers; [ tlvince ];

  options.services.immich-kiosk = {
    enable = mkEnableOption "Immich Kiosk slideshow service";

    package = mkPackageOption pkgs "immich-kiosk" { };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to open the firewall for the immich-kiosk port.
      '';
    };

    settings = mkOption {
      type = types.nullOr (
        types.submodule {
          freeformType = format.type;
          options = {
            immich_url = mkOption {
              type = types.str;
              default = lib.attrByPath [ "services" "immich" "settings" "server" "externalDomain" ] "" config;
              defaultText = lib.literalExpression ''
                config.services.immich.settings.server.externalDomain or ""
              '';
              description = ''
                URL of the immich instance.
              '';
            };

            kiosk.port = mkOption {
              type = types.port;
              default = 3000;
              description = ''
                Port on which immich-kiosk will listen.
              '';
            };
          };
        }
      );
      default = null;
      description = ''
        Configuration for immich-kiosk. See
        <https://docs.immichkiosk.app/configuration/>
        for available options. Secret values can be loaded from files using
        `{ _secret = "/path/to/secret"; }`.
      '';
      example = lib.literalExpression ''
        {
          immich_url = "https://immich.example.com";
          immich_api_key = {
            _secret = "/run/secrets/immich-kiosk-api-key";
          };
          albums = [
            "4fa933cf-051f-4621-9ac7-8d06776c261c"
            "6466548c-4995-4fb5-ab1f-f63cc9ff3e5f"
          ];
          duration = 30;
          layout = "splitview";
          disable_ui = true;
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.immich-kiosk = {
      description = "Immich Kiosk slideshow service";
      after = [ "immich-server.service" ];
      wantedBy = [ "multi-user.target" ];

      preStart = mkIf (cfg.settings != null) ''
        install -m 700 -d ${configDir}
        ${secretsReplacement.script}
      '';

      serviceConfig = {
        DynamicUser = true;
        ExecStart = lib.getExe cfg.package;
        Group = "immich-kiosk";
        LoadCredential = secretsReplacement.credentials;
        Restart = "on-failure";
        RestartSec = 10;
        RuntimeDirectory = "immich-kiosk";
        SyslogIdentifier = "immich-kiosk";
        Type = "simple";
        User = "immich-kiosk";
        WorkingDirectory = "/run/immich-kiosk";

        # Hardening
        CapabilityBoundingSet = [ "" ];
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ kioskPort ];
  };
}
