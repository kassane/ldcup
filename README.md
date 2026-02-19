ldcup
=====

[![Static Badge](https://img.shields.io/badge/v2.111.0%20(stable)-f8240e?logo=d&logoColor=f8240e&label=runtime)](https://dlang.org/download.html)
![Latest release](https://img.shields.io/github/v/release/kassane/ldcup?include_prereleases&label=latest)
[![Artifacts](https://github.com/kassane/ldcup/actions/workflows/ci.yml/badge.svg)](https://github.com/kassane/ldcup/actions/workflows/ci.yml)

<div align="center">

![Image](https://github.com/user-attachments/assets/c4259d2a-630f-414d-9aa6-1fe0c2ba4c23)

</div>

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
$ ldcup install ldc2-${version}
# or
$ ldcup install redub # redub build-system (dub fork) - need ldc2 installed
$ ldcup list # list installed compilers in default path directory
$ ldcup list --remote # list all available compiler releases
$ ldcup uninstall ldc2-${version}
$ ldcup run -- --version # run ldc2 with --version flag

## Custom path directory
$ ldcup list --install-dir=custom-path # list installed compilers in custom path directory
# or set LDC2_ROOTPATH environment variable
$ LDC2_ROOTPATH=customPath ldcup list # list installed compilers in custom path directory
```

### Helper

```console
$ ldcup                                         
Usage: ldcup [command] [options]
Commands:
  install [compiler]    Install a compiler (default: ldc2-latest)
  uninstall <compiler>  Uninstall an installed compiler
  list                  List installed compilers
  run -- <flags>        Run ldc2 with the given flags

Compiler specifiers:
  ldc2-latest           Latest stable LDC2 release (default)
  ldc2-beta             Latest beta LDC2 release
  ldc2-nightly          Latest nightly/CI build
  ldc2-<version>        Specific version, e.g. ldc2-1.39.0
  opend-latest          Latest OpenD release
  redub                 Install the redub build tool

Options:
  --install-dir=DIR     Override installation directory
  --platform=OS-ARCH    Override platform (e.g. linux-x86_64)
  --remote              (list) Show all available remote releases
  --verbose, -v         Enable verbose output
  --help, -h            Show this help message
```

### License

[Apache-2.0](LICENSE)
