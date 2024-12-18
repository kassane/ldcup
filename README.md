# ldcup

Download and manage ldc2 compiler.

> [!NOTE]
> For DMD, see [dlang website - Downloads](https://dlang.org/download).

Inspired by [rustup](https://github.com/rust-lang/rustup.rs) and [zigup](https://github.com/marler8997/zigup).

## Usage
```bash
$ ldcup install # default latest version
# or
$ ldcup install ldc2-master # latest-CI version
# or
$ ldcup install ldc2-${version} # optional: -v
$ ldcup list
$ ldcup uninstall ldc2-${version}
```

## Helper
```bash
$ ldcup                                         
Usage: ldcup [command] [options]
Commands:
  install [compiler]   Install a D compiler (default: ldc2-latest)
  uninstall [compiler] Uninstall a specific compiler
  list                 List installed compilers
  --verbose, -v        Enable verbose output
  --install-dir=DIR    Specify the installation directory
  --help, -h           Show this help message
```

## License

[Apache-2.0](LICENSE)
