module app;

import impl;
import std.stdio : writeln, writefln;
import std.string : format, startsWith, endsWith, toLower, split;
import std.algorithm : canFind, countUntil;
import std.exception : enforce;
import std.meta : AliasSeq;

// std.algorithm.comparison.among requires an import; use a helper instead.
private bool among(T, Args...)(T val, Args choices)
{
    foreach (c; choices)
        if (val == c)
            return true;
    return false;
}

struct Args
{
    bool help;
    bool verbose;
    bool remote;
    string installDir;
    string platform;
    string command;
    string compiler = "ldc2-latest";
    string[] compilerArgs;
}

void printHelp(string programName) @safe
{
    writefln("Usage: %s <command> [compiler] [options]", programName);
    writeln();
    writeln("Commands:");
    writeln("  install [compiler]    Install a compiler (default: ldc2-latest)");
    writeln("  uninstall <compiler>  Uninstall an installed compiler");
    writeln("  list                  List installed compilers");
    writeln("  run -- <flags>        Run ldc2 with the given flags");
    writeln();
    writeln("Compiler specifiers:");
    writeln("  ldc2-latest           Latest stable LDC2 release (default)");
    writeln("  ldc2-beta             Latest beta LDC2 release");
    writeln("  ldc2-nightly          Latest nightly/CI build");
    writeln("  ldc2-<version>        Specific version, e.g. ldc2-1.39.0");
    writeln("  opend-latest          Latest OpenD release");
    writeln("  redub                 Install the redub build tool");
    writeln();
    writeln("Options:");
    writeln("  --install-dir=DIR     Override installation directory");
    writeln("  --platform=OS-ARCH    Override platform (e.g. linux-x86_64)");
    writeln("  --remote              (list) Show all available remote releases");
    writeln("  --verbose, -v         Enable verbose output");
    writeln("  --help, -h            Show this help message");
}

/// Strip a leading "v" from a version tag so "v1.39.0" → "ldc2-1.39.0".
private string normaliseCompilerSpec(string spec) @safe pure
{
    // e.g. user typed "v1.39.0" — treat as "ldc2-1.39.0"
    if (spec.startsWith("v") && !spec.startsWith("verbose"))
        return "ldc2-" ~ spec[1 .. $];
    return spec;
}

Args parseArgs(string[] argv) @safe
{
    Args parsed;

    for (size_t i = 1; i < argv.length; ++i)
    {
        string arg = argv[i];

        if (arg == "--help" || arg == "-h")
            parsed.help = true;
        else if (arg == "--verbose" || arg == "-v")
            parsed.verbose = true;
        else if (arg == "--remote")
            parsed.remote = true;
        else if (arg.startsWith("--platform="))
            parsed.platform = arg["--platform=".length .. $];
        else if (arg.startsWith("--install-dir="))
            parsed.installDir = arg["--install-dir=".length .. $];
        else if (arg == "--")
        {
            // Everything after "--" is passed verbatim to the compiler.
            parsed.compilerArgs = argv[i + 1 .. $];
            break;
        }
        else if (arg.startsWith("ldc2-") || arg.startsWith("opend-"))
            parsed.compiler = normaliseCompilerSpec(arg);
        else if (arg.canFind("redub"))
            parsed.compiler = arg;
        else if (parsed.command.empty)
            parsed.command = arg;
        else
            throw new Exception("Unknown argument: " ~ arg);
    }

    return parsed;
}

int main(string[] argv) @safe
{
    Args parsed;
    try
        parsed = parseArgs(argv);
    catch (Exception e)
    {
        writefln("Error: %s", e.msg);
        writeln("Run with --help for usage information.");
        return 1;
    }

    if (parsed.help || argv.length < 2)
    {
        printHelp(argv[0]);
        return 0;
    }

    if (parsed.compiler.among("dmd", "gdc"))
    {
        writeln("Error: only ldc2 and opend compilers are supported.");
        return 1;
    }

    if (parsed.command.empty)
    {
        writeln("Error: no command specified.");
        printHelp(argv[0]);
        return 1;
    }

    try
    {
        auto manager = new CompilerManager(parsed.installDir, parsed.platform);
        manager.verbose = parsed.verbose;

        switch (parsed.command)
        {
        case "install":
            manager.installCompiler(parsed.compiler);
            break;

        case "uninstall":
            manager.uninstallCompiler(parsed.compiler);
            break;

        case "list":
            if (parsed.remote)
                manager.listLDCVersions();
            else
                foreach (c; manager.listInstalledCompilers())
                    writeln(c);
            break;

        case "run":
            manager.runCompiler(parsed.compiler, parsed.compilerArgs);
            break;

        default:
            writefln("Error: unknown command '%s'.", parsed.command);
            printHelp(argv[0]);
            return 1;
        }
    }
    catch (Exception e)
    {
        writefln("Error: %s", e.msg);
        return 1;
    }

    return 0;
}
