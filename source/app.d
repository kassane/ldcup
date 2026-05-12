module app;

import impl;

version(unittest) {} else
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
            enforce(parsed.compilerSet, "uninstall requires a compiler specifier, e.g. ldc2-1.42.0");
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
