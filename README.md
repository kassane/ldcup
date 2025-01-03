# ldcup

Download and manage LDC2 compiler. [D and OpenD]

> [!NOTE]
> For DMD, see [dlang website - Downloads](https://dlang.org/download).

Inspired by [rustup](https://github.com/rust-lang/rustup.rs) and [zigup](https://github.com/marler8997/zigup).

## Usage

- Download [precompiled binaries](https://github.com/kassane/ldcup/releases) and extract it.
- Add `ldcup` to your `$PATH`.
- Run `ldcup` commands.
```bash
$ ldcup install # default latest version
# or
$ ldcup install opend-latest # opend-ldc2 compiler
# or
$ ldcup install ldc2-master # latest-CI version
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

## Helper
```console
$ ldcup                                         
Usage: ldcup [command] [options]
Commands:
  install [compiler]   Install a ldc2 compiler (default: ldc2-latest)
  uninstall [compiler] Uninstall a specific compiler
  list                 List installed compilers
  run -- [compiler-flags] Run a ldc2 compiler with specified flags
  --install-dir=DIR    Specify the installation directory
  --verbose, -v        Enable verbose output
  --remote             List all available compiler releases
  --help, -h           Show this help message
```

## License

[Apache-2.0](LICENSE)
