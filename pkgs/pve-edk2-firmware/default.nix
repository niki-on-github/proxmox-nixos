{
  lib,
  python3,
  pkgs, 
  pkgsCross,
  stdenvNoCC, 
  fetchgit,
  ... 
}:

stdenvNoCC.mkDerivation rec {
  pname = "pve-edk2-firmware";
  version = "4.2023.08-4";

  src = fetchgit {
    url = "git://git.proxmox.com/git/${pname}.git";
    rev = "17443032f78eaf9ae276f8df9d10c64beec2e048";
    sha256 = "sha256-19frOpnL8xLWIDw58u1zcICU9Qefp936LteyfnSIMCw=";
    fetchSubmodules = true;
  };

  buildInputs = [ ];

  hardeningDisable = [ "format" "fortify" "trivialautovarinit" ];

  nativeBuildInputs = with pkgs; [
    dpkg fakeroot qemu
    bc dosfstools acpica-tools mtools nasm libuuid
    qemu-utils libisoburn python3
    pkgsCross.aarch64-multiplatform.buildPackages.gcc
    pkgsCross.riscv64.buildPackages.gcc
    pkgsCross.gnu64.buildPackages.gcc
  ];

  prePatch = 
  let
    pythonPath = python3.pkgs.makePythonPath (with python3.pkgs; [ pexpect ]);
  in
  ''
    patchShebangs .
    substituteInPlace ./debian/rules \
      --replace-warn /bin/bash ${pkgs.bash}/bin/bash
    substituteInPlace ./Makefile ./debian/rules \
      --replace-warn /usr/share/dpkg ${pkgs.dpkg}/share/dpkg
    substituteInPlace ./debian/rules \
      --replace-warn 'PYTHONPATH=$(CURDIR)/debian/python' 'PYTHONPATH=$(CURDIR)/debian/python:${pythonPath}'

    # Skip dh calls because we don't need debhelper
    substituteInPlace ./debian/rules \
      --replace-warn 'dh $@' ': dh $@'

    # Patch cross compiler paths
    substituteInPlace ./debian/rules ./**/CMakeLists.txt \
      --replace-warn 'aarch64-linux-gnu-' 'aarch64-unknown-linux-gnu-'
    substituteInPlace ./debian/rules ./**/CMakeLists.txt \
      --replace-warn 'riscv64-linux-gnu-' 'riscv64-unknown-linux-gnu-'
  '';

  buildPhase = 
  let
    mainVersion = builtins.head (lib.splitString "-" version);
  in
  ''
    # Set up build directory (src)
    make ${pname}_${mainVersion}.orig.tar.gz
    pushd ${pname}-${mainVersion}

    # Apply patches using dpkg 
    dpkg-source -b .

    make -f debian/rules override_dh_auto_build
  '';

  installPhase = ''
    # Patch paths in produced .install scripts
    substituteInPlace ./debian/*.install \
      --replace-warn '/usr/share/pve-edk2-firmware' "$out"

    # Copy files as mentioned in install scripts
    for ins in ./debian/*.install; do
      while IFS= read -r line; do
        read -ra paths <<< "$line"
        dest="''${paths[-1]}"
        mkdir -p "$dest"
        for src in "''${paths[@]::''${#paths[@]}-1}"; do
          cp $src "$dest"
        done
      done < "$ins"
    done
  '';

  meta = {
    description = "edk2 based UEFI firmware modules for virtual machines";
    homepage = "git://git.proxmox.com/git/${pname}.git";
    maintainers = with lib.maintainers; [ ];
  };
 }