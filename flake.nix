{
  description = "gh-dotenv-sync - sync .env files to GitHub Environment Secrets";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }: let
    systems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    forEachSystem = nixpkgs.lib.genAttrs systems;
  in {
    packages = forEachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = self.packages.${system}.gh-dotenv-sync;
      gh-dotenv-sync = pkgs.stdenv.mkDerivation {
        name = "gh-dotenv-sync";
        src = ./.;

        buildInputs = [ pkgs.makeWrapper ];

        installPhase = ''
          mkdir -p $out/bin
          cp ${./gh-dotenv-sync.sh} $out/bin/gh-dotenv-sync
          chmod +x $out/bin/gh-dotenv-sync

          wrapProgram $out/bin/gh-dotenv-sync \
            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.gh pkgs.git pkgs.gnugrep pkgs.diffutils pkgs.coreutils ]}
        '';
      };
    });
  };
}
