import impl;

void main(string[] args) @safe
{
	bool hasHelp = false;
	bool hasVerbose = false;
	bool hasAllVersion = false;
	string installdir;
	string command;
	string compiler = "ldc2-latest";

	foreach (arg; args[1 .. $])
	{
		if (arg == "--help" || arg == "-h")
			hasHelp = true;
		else if (arg == "--verbose" || arg == "-v")
			hasVerbose = true;
		else if (arg.startsWith("--install-dir="))
			installdir = arg.split("=")[1];
		else if (arg.startsWith("ldc2-"))
			compiler = arg;
		else if (arg == "--remote")
			hasAllVersion = true;
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
		writeln("  install [compiler]   Install a D compiler (default: ldc2-latest)");
		writeln("  uninstall [compiler] Uninstall a specific compiler");
		writeln("  list                 List installed compilers");
		writeln("  --install-dir=DIR    Specify the installation directory");
		writeln("  --verbose, -v        Enable verbose output");
		writeln("  --remote             List all available compiler releases");
		writeln("  --help, -h           Show this help message");
		return;
	}

	auto installer = new CompilerManager(installdir);

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
	default:
		writeln("Unknown command. Use install, uninstall, or list.");
	}
}
