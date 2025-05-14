{
    description = "kwja packaged with uv + uv2nix";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/release-24.11";
        cuda-nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
        pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
        uv2nix.url = "github:pyproject-nix/uv2nix";

        pyproject-build-systems = {
            url = "github:pyproject-nix/build-system-pkgs";
            inputs.nixpkgs.follows = "nixpkgs";
            inputs.pyproject-nix.follows = "pyproject-nix";
            inputs.uv2nix.follows = "uv2nix";
        };
    };

    outputs = { self, nixpkgs, cuda-nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
        let
            system = "x86_64-linux";

            cuda-pkgs = import cuda-nixpkgs {
                inherit system;
                config.allowUnfree = true;
            };

            secomDer = pkgs.fetchurl {
                url    = "https://repository.secomtrust.net/SC-Root2/SCRoot2ca.cer";
                sha256 = "sha256-UTss7LgQ1M3l3YU5Gt/Gwt1g2Hu3NtK1IUhKpHoOvvY=";
            };
            niiDer = pkgs.fetchurl {
                url    = "https://repo1.secomtrust.net/sppca/nii/odca4/nii-odca4g7rsa.cer";
                sha256 = "sha256-YD23B6WEADvtbx1D3NTq4TzRjXmOgn3i86MfMZP8Daw=";
            };

            extraCaBundle = pkgs.runCommand "secom-nii-extra.pem" { nativeBuildInputs = [ pkgs.openssl ]; } ''
                    openssl x509 -inform DER -in ${secomDer} -out secom.pem
                    openssl x509 -inform DER -in ${niiDer}  -out nii.pem
                    cat secom.pem nii.pem > $out
            '';

            pkgs = import nixpkgs {
                inherit system;

                overlays = [
                    (final: prev: {
                        cacert = prev.cacert.override {
                            extraCertificateFiles = [
                                extraCaBundle
                            ];
                        };
                    })
                ];
            };

            workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

            overlay = workspace.mkPyprojectOverlay {
                sourcePreference = "wheel";
            };

            pythonBase = (pkgs.callPackage pyproject-nix.build.packages { python = pkgs.python312; }).overrideScope (pkgs.lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                overlay
            ]);

            pythonSet = pythonBase.overrideScope (final: prev: {
                "antlr4-python3-runtime" = prev."antlr4-python3-runtime".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.setuptools final.wheel ];
                });
                "jaconv" = prev."jaconv".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools final.wheel ];
                });
                "pure-cdb" = prev."pure-cdb".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.setuptools final.wheel ];
                });
                "seqeval" = prev."seqeval".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.setuptools final.wheel ];
                });

                "torch" = prev.torch.overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
                        cuda-pkgs.cudaPackages.cudatoolkit
                        cuda-pkgs.cudaPackages.libcublas
                        cuda-pkgs.cudaPackages.libcusparse
                        cuda-pkgs.cudaPackages.cusparselt
                        cuda-pkgs.cudaPackages.libcufft
                        cuda-pkgs.cudaPackages.cudnn
                        cuda-pkgs.cudaPackages.nccl
                        cuda-pkgs.cudaPackages.libcufile
                        cuda-pkgs.cudaPackages.libnvjitlink
                        cuda-pkgs.rdma-core
                    ];

                    autoPatchelfIgnoreMissingDeps = [
                        "libcuda.so.1"
                    ];
                });
                

                "nvidia-cusolver-cu12" = prev."nvidia-cusolver-cu12".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                        cuda-pkgs.cudaPackages.libnvjitlink
                        cuda-pkgs.cudaPackages.libcublas
                        cuda-pkgs.cudaPackages.libcusparse
                    ];
                });
                "nvidia-cufile-cu12" = prev."nvidia-cufile-cu12".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
                        cuda-pkgs.rdma-core
                    ];
                });
                "nvidia-cusparse-cu12" = prev."nvidia-cusparse-cu12".overrideAttrs (old: {
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
                        cuda-pkgs.cudaPackages.libnvjitlink
                    ];
                });
            });

            kwjaEnv = pythonSet.mkVirtualEnv "kwja-env" workspace.deps.default;
        in {
            packages.${system}.default = kwjaEnv;

            apps.${system}.default = {
                type = "app";
                program = "${kwjaEnv}/bin/kwja";
            };

            devShells.${system}.default = pkgs.mkShell {
                packages = [ kwjaEnv pkgs.uv ];
                env = {
                    UV_PYTHON = "${kwjaEnv}/bin/python";
                    UV_PYTHON_DOWNLOADS = "never";
                    UV_NO_SYNC = "1";
                };
                shellHook = ''
                    unset PYTHONPATH
                '';
            };
        };
}
