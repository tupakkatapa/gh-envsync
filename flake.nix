{
  description = "gh-envsync - sync .env files to GitHub Environment Secrets";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }: let
    systems = [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
    forEachSystem = nixpkgs.lib.genAttrs systems;
  in {
    packages = forEachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = self.packages.${system}.gh-envsync;
      gh-envsync = pkgs.stdenv.mkDerivation {
        name = "gh-envsync";
        src = ./.;

        buildInputs = [ pkgs.makeWrapper ];

        installPhase = ''
          mkdir -p $out/bin
          cp ${./gh-envsync.sh} $out/bin/gh-envsync
          chmod +x $out/bin/gh-envsync

          wrapProgram $out/bin/gh-envsync \
            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.gh pkgs.git pkgs.gnugrep pkgs.diffutils pkgs.coreutils ]}
        '';
      };
    });
  };
}
