import impl;

struct Args
{
    bool help, verbose, remote;
    string installDir, platform, command, compiler = "ldc2-latest";
    string[] compilerArgs;
}

void main(string[] args) @safe
{
    Args parsed;
    foreach (arg; args[1 .. $])
    {
        if (arg == "--help" || arg == "-h") parsed.help = true;
        else if (arg == "--verbose" || arg == "-v") parsed.verbose = true;
        else if (arg == "--remote") parsed.remote = true;
        else if (arg.startsWith("--platform=")) parsed.platform = arg.split("=")[1];
        else if (arg.startsWith("--install-dir=")) parsed.installDir = arg.split("=")[1];
        else if (arg.startsWith("ldc2-") || arg.startsWith("opend-")) parsed.compiler = arg.replace("v", "");
        else if (arg.canFind("redub")) parsed.compiler = arg;
        else if (arg == "--") parsed.compilerArgs = args[args.countUntil(arg) + 1 .. $];
        else if (parsed.command.empty) parsed.command = arg;
        else throw new Exception("Unknown flag: %s".format(arg));
    }

    if (parsed.help || args.length < 2)
    {
        writeln("Usage: ", args[0], " [command] [options]");
        writeln("Commands:");
        writeln("  install [compiler]   Install a compiler (default: ldc2-latest)");
        writeln("  uninstall [compiler] Uninstall a compiler");
        writeln("  list                 List installed compilers");
        writeln("  run -- <flags>       Run ldc2 with flags");
        writeln("Options:");
        writeln("  --install-dir=DIR    Installation directory");
        writeln("  --platform=PLATFORM  Platform (e.g., linux-x86_64)");
        writeln("  --verbose, -v        Verbose output");
        writeln("  --remote             List all available releases");
        writeln("  --help, -h           Show this help");
        return;
    }

    enforce(!parsed.compiler.among("dmd", "gdc"), "Only ldc2 compiler is supported");
    enforce(!parsed.command.empty, "No command specified");

    auto installer = new CompilerManager(parsed.installDir, parsed.platform);
    if (parsed.verbose) installer.verbose = true;

    final switch (parsed.command)
    {
        case "install": installer.installCompiler(parsed.compiler); break;
        case "uninstall": installer.uninstallCompiler(parsed.compiler); break;
        case "list": parsed.remote ? installer.listLDCVersions : writeln(installer.listInstalledCompilers); break;
        case "run": installer.runCompiler(parsed.compiler, parsed.compilerArgs); break;
    }
}