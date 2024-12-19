import std;

enum OS
{
	android,
	linux,
	osx,
	windows
}

enum Arch
{
	aarch64,
	armv7a,
	multilib,
	universal,
	x86_64
}

class CompilerManager
{
	private
	{
		string root;
		string compilerPath;
		string toolchainExtractPath;
		string compilerVersion;
		version (Windows)
			immutable string ext = ".7z";
		else
			immutable string ext = ".tar.xz";
		bool verbose;
		OS currentOS;
		Arch currentArch;
	}

	this(string installRoot) @safe
	{
		if (!installRoot.empty)
			environment["DC_PATH"] = installRoot;
		else if (environment.get("DC_PATH").empty)
			environment["DC_PATH"] = defaultInstallRoot();

		root = environment.get("DC_PATH");

		if (!exists(root))
			mkdir(root);

		verbose = false;
		detectPlatform();

		debug writeln("Installing to " ~ root);
	}

	private string defaultInstallRoot() @safe
	{
		version (Windows)
			return buildPath(environment.get("LOCALAPPDATA", expandTilde("~")), "dlang");
		else version (Posix)
			return buildPath(environment.get("HOME", expandTilde("~")), ".dlang");
		else
			return expandTilde("~/dlang");
	}

	private void detectPlatform() @safe @nogc
	{
		version (OSX)
			currentOS = OS.osx;
		else version (Android)
			currentOS = OS.android;
		else version (linux)
			currentOS = OS.linux;
		else version (Windows)
			currentOS = OS.windows;
		else
			static assert(0, "Unsupported operating system");

		version (X86_64)
			currentArch = Arch.x86_64;
		else version (ARM)
			currentArch = Arch.armv7a;
		else version (AArch64)
			currentArch = Arch.aarch64;
		else
			static assert(0, "Unsupported architecture");
	}

	void installCompiler(string compilerSpec) @safe
	{
		log("Installing compiler: " ~ compilerSpec);
		auto resolvedCompiler = resolveLatestVersion(compilerSpec);

		auto downloadUrl = getCompilerDownloadUrl(resolvedCompiler);
		downloadAndExtract(downloadUrl, buildPath(root, resolvedCompiler));

		generateActivationScripts(resolvedCompiler);
	}

	private string resolveLatestVersion(string compilerSpec) @trusted
	{
		// If no specific version is provided, fetch the latest version
		if (compilerSpec.endsWith("latest") || compilerSpec.empty)
		{
			try
			{
				auto response = get("https://ldc-developers.github.io/LATEST"); // @system
				string latestVersion = strip(response.to!string);
				log("Resolved latest version: ldc2-" ~ latestVersion);
				return "ldc2-" ~ latestVersion;
			}
			catch (Exception e)
			{
				log("Error resolving latest version: " ~ e.msg);
				throw e;
			}
		}
		else if (compilerSpec.endsWith("nightly") || compilerSpec.endsWith("master"))
		{
			try
			{
				auto response = get("https://github.com/ldc-developers/ldc/commits/master.atom"); // @system
				auto commitHash = strip(response.split(
						"<id>tag:github.com,2008:Grit::Commit/")[1].split("</id>")[0][0 .. 8]);
				log("Resolved nightly version: ldc2-" ~ commitHash.to!string);
				return "ldc2-" ~ commitHash.to!string;
			}
			catch (Exception e)
			{
				log("Error resolving nightly version: " ~ e.msg);
				throw e;
			}
		}
		// If a specific version is provided, return it
		return compilerSpec;
	}

	private string getCompilerDownloadUrl(string compilerSpec) @safe
	{
		string compilerVer = resolveLatestVersion(compilerSpec);

		version (OSX)
			this.currentArch = Arch.universal;
		else version (Windows)
			this.currentArch = Arch.multilib;

		if (compilerSpec.startsWith("ldc2-"))
		{
			compilerVersion = compilerVer["ldc2-".length .. $];
			log("Downloading LDC2 for version: " ~ compilerVersion);

			return compilerVersion.match(r"^\d+(\.\d+)*$")
				? fmt("https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s-%s%s",
					compilerVersion, compilerVersion, this.currentOS, this.currentArch, this.ext) : fmt(
					"https://github.com/ldc-developers/ldc/releases/download/CI/ldc2-%s-%s-%s%s",
					compilerVersion, this.currentOS, this.currentArch, this.ext);
		}

		throw new Exception("Unknown compiler: " ~ compilerSpec);
	}

	private void download(string url, string fileName) @trusted
	{
		log("Downloading from URL: " ~ url);
		auto buf = appender!(ubyte[])();
		size_t contentLength;

		auto http = HTTP(url); // unsafe/@system (need libcurl)
		http.method = HTTP.Method.get;
		http.onReceiveHeader((in k, in v) {
			if (k == "content-length")
				contentLength = to!size_t(v);
		});

		// Progress bar
		int barWidth = 50;
		http.onReceive((data) {
			buf.put(data);
			if (contentLength > 0)
			{
				float progress = cast(float) buf.data.length / contentLength;
				int pos = cast(int)(barWidth * progress);

				write("\r[");
				for (int i = 0; i < barWidth; ++i)
				{
					if (i < pos)
						write("=");
					else if (i == pos)
						write(">");
					else
						write(" ");
				}
				writef("] %d%%", cast(int)(progress * 100));
				stdout.flush();
			}
			return data.length;
		});

		http.dataTimeout = dur!"msecs"(0);
		http.perform();
		immutable sc = http.statusLine().code;
		enforce(sc / 100 == 2 || sc == 302,
			fmt("HTTP request returned status code %s", sc));
		log("\nDownload complete");

		auto file = File(fileName, "wb");
		scope (success)
			file.close();
		file.rawWrite(buf.data);
	}

	private void downloadAndExtract(string url, string targetPath) @safe
	{
		if (!exists(targetPath))
		{
			download(url, targetPath ~ ext);

			// Extract the downloaded tarball
			version (Windows)
				extract7z(targetPath ~ ext, targetPath);
			else
				extractTarXZ(targetPath ~ ext, targetPath);
			// Remove the downloaded tarball
			remove(targetPath ~ ext);

			log("Extracted compiler to " ~ targetPath);

			toolchainExtractPath = buildPath(targetPath, fmt("ldc2-%s-%s-%s", this.compilerVersion, this
					.currentOS, this
					.currentArch));
		}
		else
		{
			toolchainExtractPath = buildPath(targetPath, fmt("ldc2-%s-%s-%s", this.compilerVersion, this
					.currentOS, this
					.currentArch));

			writeln("Compiler already exists at " ~ toolchainExtractPath);
		}
	}

	private void extractTarXZ(string tarFile, string destination) @safe
	{
		immutable tarExe = findProgram("tar");
		log("Extracting TarXZ: " ~ tarFile);
		if (exists(destination))
			rmdirRecurse(destination);

		mkdirRecurse(destination);
		auto pid = spawnProcess([
			tarExe, "xf", tarFile, fmt("--directory=%s", destination)
		]);
		enforce(pid.wait() == 0, "Extraction failed");
	}

	private void extract7z(string sevenZipFile, string destination) @safe
	{
		immutable sevenZipExe = findProgram("7z");
		log("Extracting 7z: " ~ sevenZipFile);
		if (exists(destination))
			rmdirRecurse(destination);

		mkdirRecurse(destination);

		auto pid = spawnProcess([
			sevenZipExe, "x", sevenZipFile, fmt("-o%s", destination)
		]);
		enforce(pid.wait() == 0, "7z extraction failed");
	}

	private void generateActivationScripts(string compilerName) @safe
	{
		compilerPath = buildPath(root, compilerName);
		string scriptsDir = buildPath(compilerPath, "activation");
		mkdirRecurse(scriptsDir);

		// Bash activation script
		string bashScript = buildPath(scriptsDir, "activate.sh");
		std.file.write(bashScript, q"[#!/bin/bash
		export PATH="$PATH:COMPILER_PATH/bin"
		export DC_PATH=COMPILER_PATH
		export DC=COMPILER_PATH/bin/ldmd2
		]".replace("COMPILER_PATH", toolchainExtractPath));

		// Fish activation script
		string fishScript = buildPath(scriptsDir, "activate.fish");
		std.file.write(fishScript, q"[#!/usr/bin/env fish
		set -x PATH $PATH COMPILER_PATH/bin
		set -x DC_PATH COMPILER_PATH
		set -x DC COMPILER_PATH/bin/ldmd2
		]".replace("COMPILER_PATH", toolchainExtractPath));

		// Windows batch script
		string batchScript = buildPath(scriptsDir, "activate.bat");
		std.file.write(batchScript, q"[@echo off
		set PATH=%PATH%;COMPILER_PATH\bin
		set DC_PATH=COMPILER_PATH
		set DC=COMPILER_PATH\bin\ldmd2
		]".replace("COMPILER_PATH", toolchainExtractPath));

		log("Generated activation scripts for " ~ compilerName);

		version (Posix)
			writefln("\nrun\nsource %s", bashScript);
		else
			writefln("\nrun\n %s", batchScript);
	}

	void uninstallCompiler(string compilerName) @safe
	{
		log("Uninstalling compiler: " ~ compilerName);
		auto compilerPath = buildPath(root, compilerName);
		if (exists(compilerPath))
		{
			rmdirRecurse(compilerPath);
		}
		else
		{
			throw new Exception("Compiler not installed: " ~ compilerName);
		}
	}

	void listLDCVersions() @safe
	{
		log("Listing LDC versions");
		string githubUrl = "https://api.github.com/repos/ldc-developers/ldc/releases";
		auto results = getGitHubList(githubUrl);
		auto versions = results.map!(release => release["tag_name"].str).array;
		writeln(versions.sort().to!string);
	}

	JSONValue[] getGitHubList(string baseURL) @trusted
	{
		JSONValue[] results;
		int perPage = 100;
		int pageNumber = 1;

		while (true)
		{
			string url = fmt("%s?per_page=%d&page=%d", baseURL, perPage, pageNumber);
			auto response = get(url);
			JSONValue json = parseJSON(response);
			JSONValue[] responseResults = json.array;

			if (responseResults.length == 0)
				break;

			results ~= responseResults;
			pageNumber++;

			if (responseResults.length < perPage)
				break;
		}

		return results;
	}

	string[] listInstalledCompilers() @trusted
	{
		log("Listing installed compilers");
		return dirEntries(root, SpanMode.shallow) // @system
			.filter!(entry => entry.isDir)
			.map!(entry => entry.name.baseName)
			.array;
	}

	void log(string message) @safe
	{
		if (verbose)
		{
			writeln(message);
		}
	}
}

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

private string fmt(Args...)(string fmt, auto ref Args args) @safe
{
	auto app = appender!string();
	formattedWrite(app, fmt, args);
	return app.data;
}

private string findProgram(string programName) @safe
{
	string[] paths = environment.get("PATH").split(pathSeparator);
	foreach (path; paths)
	{
		string fullPath = buildPath(path, programName);
		version (Windows)
		{
			fullPath ~= ".exe";
		}
		if (exists(fullPath) && isFile(fullPath))
		{
			return fullPath;
		}
	}
	throw new Exception("Could not find program: " ~ programName);
}
