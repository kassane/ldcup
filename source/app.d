import impl;

void main(string[] args) @safe
{
	bool hasHelp = false;
	bool hasVerbose = false;
	bool hasAllVersion = false;
	string installdir;
	string platform;
	string command;
	string compiler = "ldc2-latest";
	string[] compilerArgs;

	foreach (arg; args[1 .. $])
	{
		if (arg == "--help" || arg == "-h")
			hasHelp = true;
		else if (arg == "--verbose" || arg == "-v")
			hasVerbose = true;
		else if (arg.startsWith("--platform="))
			platform = arg.split("=")[1];
		else if (arg.startsWith("--install-dir="))
			installdir = arg.split("=")[1];
		else if (arg.startsWith("ldc2-") || arg.startsWith("opend-"))
		{
			// Remove the 'v' from version string
			if (arg.startsWith("ldc2-v") || arg.startsWith("opend-v"))
				compiler = arg[0 .. $].replace("v", "");
			else
				compiler = arg;
		}
		else if (arg.canFind("redub"))
			compiler = arg;
		else if (arg == "--remote")
			hasAllVersion = true;
		else if (arg.endsWith("--"))
		{
			auto flagIndex = countUntil(args[1 .. $], "--");
			if (flagIndex != -1)
			{
				compilerArgs = args[(flagIndex + 1) + 1 .. $];
				break;
			}
		}
		else if (command == "")
			command = arg;
		else
			throw new Exception("Unknown flag: " ~ arg);

		if (arg == "dmd" || arg == "gdc")
		{
			throw new Exception("Only ldc2 compiler is allowed.");
		}
	}

	if (hasHelp || args.length < 2)
	{
		writefln("Usage: %s [command] [options]", args[0]);
		writeln("Commands:");
		writeln("  install [compiler]   Install a ldc2 compiler (default: ldc2-latest)");
		writeln("  uninstall [compiler] Uninstall a specific compiler");
		writeln("  list                 List installed compilers");
		writeln("  run -- <ldc2-flags>  Run a ldc2 compiler with specified flags");
		writeln("  --install-dir=DIR    Specify the installation directory");
		writeln("  --platform=PLATFORM  Specify the platform (e.g., linux-x86_64)");
		writeln("  --verbose, -v        Enable verbose output");
		writeln("  --remote             List all available compiler releases");
		writeln("  --help, -h           Show this help message");
		return;
	}

	auto installer = new CompilerManager(installdir, platform);

	if (hasVerbose)
		installer.verbose = true;

	switch (command)
	{
	case "install":
		installer.installCompiler(compiler);
		break;
	case "uninstall":
		installer.uninstallCompiler(compiler);
		break;
	case "list":
		if (hasAllVersion)
			installer.listLDCVersions;
		else
			writeln(installer.listInstalledCompilers());
		break;
	case "run":
		installer.runCompiler(compiler, compilerArgs);
		break;
	default:
		writeln("Unknown command. Use install, uninstall, or list.");
	}
}
