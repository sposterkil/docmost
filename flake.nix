{
  description = "Docmost - open-source collaborative wiki and documentation software";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
  };

  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = (import (inputs.nixpkgs) { inherit system; });
        inherit (pkgs) lib;

        # The root of the repo contains dev leftovers (node_modules, .env,
        # build output, ...) that must not leak into the nix store.
        src = lib.cleanSourceWith {
          src = lib.cleanSource ./.;
          filter =
            path: type:
            let
              name = baseNameOf path;
            in
            !(
              type == "directory"
              && lib.elem name [
                ".direnv"
                ".jj"
                ".nx"
                ".pnpm-store"
                "data"
                "dist"
                "logs"
                "nix-package"
                "node_modules"
              ]
            )
            && !lib.elem name [
              ".env"
              ".env.dev"
              ".env.prod"
            ];
        };

        docmost = pkgs.stdenv.mkDerivation rec {
          pname = "docmost";
          version = (lib.importJSON ./package.json).version;

          inherit src;

          nativeBuildInputs = [
            pkgs.nodejs_26
            pkgs.pnpm_11
            pkgs.pnpmConfigHook
            # nx needs a tty, see https://github.com/nrwl/nx/issues/22445
            pkgs.faketty
            pkgs.makeBinaryWrapper
          ];

          pnpmDeps = pkgs.fetchPnpmDeps {
            fetcherVersion = 4;
            inherit pname version src;
            pnpm = pkgs.pnpm_11;
            pnpmWorkspaces = [
              "@docmost/editor-ext"
              "client"
              "server"
            ];
            hash = "sha256-b3kJIXHd0jRDaSii9L5UIGoiycNGH5nIaIKI1TcIlTc=";
          };

          env = {
            NX_DAEMON = "false";
            NX_INTERACTIVE = "false";
            NX_TELEMETRY_DISABLED = "true";
            # The repo pins pnpm in package.json's packageManager field, which
            # may not exactly match the nixpkgs pnpm we build with.
            npm_config_package_manager_strict = "false";
          };

          buildPhase = ''
            runHook preBuild

            faketty pnpm nx run @docmost/editor-ext:build
            faketty pnpm build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            cp -r apps $out
            cp -r packages $out/packages
            cp -r node_modules $out/node_modules
            makeWrapper ${lib.getExe pkgs.nodejs_26} $out/bin/docmost \
              --add-flags "$out/apps/server/dist/main.js" \
              --set-default NODE_ENV production

            runHook postInstall
          '';

          postFixup = ''
            # don't try to write the index.html into the read-only store
            sed -i 's/fs\.existsSync/false \&\& fs.existsSync/g' $out/apps/server/dist/integrations/static/static.module.js
          '';

          meta = {
            description = "Open-source collaborative wiki and documentation software";
            homepage = "https://docmost.com";
            changelog = "https://github.com/docmost/docmost/releases/tag/v${version}";
            license = with lib.licenses; [ agpl3Only ];
            maintainers = with lib.maintainers; [ pluiedev ];
            inherit (pkgs.nodejs_26.meta) platforms;
            mainProgram = "docmost";
          };
        };
      in
      {
        packages = {
          default = docmost;
          docmost = docmost;
        };

        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.nodejs_26
            pkgs.pnpm
            pkgs.typescript
            pkgs.typescript-language-server
          ];
        };
      }
    );
}
