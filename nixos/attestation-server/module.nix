{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.attestation-server;
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
in
{
  options.services.attestation-server = {
    enable = mkEnableOption "Hardware-based remote attestation service for monitoring the security of Android devices using the Auditor app";

    domain = mkOption {
      type = types.str;
    };

    listenHost = mkOption {
      default = "127.0.0.1";
      type = types.str;
    };

    port = mkOption {
      default = 8085;
      type = types.int;
    };

    signatureFingerprint = mkOption {
      type = types.str;
    };

    device = mkOption {
      default = "";
      type = types.str;
    };

    avbFingerprint = mkOption {
      default = "";
      type = types.str;
    };

    package = mkOption {
      default = pkgs.attestation-server.override {
        inherit (cfg) listenHost port domain signatureFingerprint device avbFingerprint;
      };
      type = types.path;
    };

    disableAccountCreation = mkOption {
      default = false;
      type = types.bool;
    };

    nginx.enable = mkOption {
      default = true;
      type = types.bool;
    };
  };

  config = mkIf cfg.enable {
    assertions = [ {
      assertion = builtins.elem cfg.device supportedDevices;
      message = "Device ${cfg.device} is currently unsupported for use with attestation server.";
    } ];

    systemd.services.attestation-server = {
      description = "Attestation Server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/AttestationServer";

        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;

        NoNewPrivileges = true;
        PrivateDevices = true;
        StateDirectory = "attestation";
        WorkingDirectory = "%S/attestation";
      };
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      virtualHosts."${config.services.attestation-server.domain}" = recursiveUpdate {
        locations."/".root = cfg.package.static;
        locations."/api/".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/api/";
        locations."/challenge".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/challenge";
        locations."/verify".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/verify";
        forceSSL = true;
      } (optionalAttrs cfg.disableAccountCreation {
        locations."/api/create_account".return = "403";
      });
    };
  };
}
