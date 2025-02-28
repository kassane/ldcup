ldcup
=====

![Latest release](https://img.shields.io/github/v/release/kassane/ldcup?include_prereleases&label=latest)
[![Artifacts](https://github.com/kassane/ldcup/actions/workflows/ci.yml/badge.svg)](https://github.com/kassane/ldcup/actions/workflows/ci.yml)
![Image](https://github.com/user-attachments/assets/c4259d2a-630f-414d-9aa6-1fe0c2ba4c23)

Download and manage LDC2 compiler. [D and OpenD]

> [!NOTE]
> For DMD, see [dlang website - Downloads](https://dlang.org/download).

Inspired by [rustup](https://github.com/rust-lang/rustup.rs) and [zigup](https://github.com/marler8997/zigup).


### Install

```bash
curl -sSf https://raw.githubusercontent.com/kassane/ldcup/main/scripts/install.sh | sh
```
or
```powershell
iwr -useb https://raw.githubusercontent.com/kassane/ldcup/main/scripts/install.ps1 | iex
```
or download [precompiled binaries](https://github.com/kassane/ldcup/releases) and extract it.

- Add `ldcup` to your `$PATH`.

### Usage

- Run `ldcup` commands.
```bash
$ ldcup install # default latest version
# or
$ ldcup install opend-latest # opend-ldc2 compiler latest-CI version
# or
$ ldcup install ldc2-beta # latest beta version
# or
$ ldcup install ldc2-[master or nightly] # latest-CI version
# or
$ ldcup install ldc2-${version} # optional: -v
$ ldcup list # list installed compilers in default path directory
$ ldcup list --remote # list all available compiler releases
$ ldcup uninstall ldc2-${version}
$ ldcup run -- --version # run ldc2 with --version flag

## Custom path directory
$ ldcup list --install-dir=custom-path # list installed compilers in custom path directory
# or set DC_PATH environment variable
$ DC_PATH=customPath ldcup list # list installed compilers in custom path directory
```

### Helper

```console
$ ldcup                                         
Usage: ldcup [command] [options]
Commands:
  install [compiler]   Install a ldc2 compiler (default: ldc2-latest)
  uninstall [compiler] Uninstall a specific compiler
  list                 List installed compilers
  run -- [compiler-flags] Run a ldc2 compiler with specified flags
  --install-dir=DIR    Specify the installation directory
  --platform=PLATFORM  Specify the platform (e.g., linux-x86_64)
  --verbose, -v        Enable verbose output
  --remote             List all available compiler releases
  --help, -h           Show this help message
```

### License

[Apache-2.0](LICENSE)
