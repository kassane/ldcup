import std;

enum OS
{
	android,
	osx,
	linux,
	freebsd,
	windows
}

enum Arch
{
	x86_64,
	x86,
	aarch64,
	multilib,
	universal
}

class CompilerManager
{
	private
	{
		string root;
		string tmpRoot;
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

	this(string installRoot = "", bool verboseMode = false)
	{
		root = installRoot.empty ? defaultInstallRoot() : expandTilde(installRoot);
		verbose = verboseMode;
		detectPlatform();
		ensureInstallDirectory();
	}

	private string defaultInstallRoot()
	{
		version (Windows)
			return buildPath(environment.get("LOCALAPPDATA", expandTilde("~")), "dlang");
		else version (Posix)
			return buildPath(environment.get("HOME", expandTilde("~")), ".dlang");
		else
			return expandTilde("~/dlang");
	}

	private void detectPlatform()
	{
		version (OSX)
			currentOS = OS.osx;
		else version (Android)
			currentOS = OS.android;
		else version (linux)
			currentOS = OS.linux;
		else version (FreeBSD)
			currentOS = OS.freebsd;
		else version (Windows)
			currentOS = OS.windows;
		else
			static assert(0, "Unsupported operating system");

		version (X86_64)
			currentArch = Arch.x86_64;
		else version (x86)
			currentArch = Arch.x86;
		else version (AArch64)
			currentArch = Arch.aarch64;
		else
			static assert(0, "Unsupported architecture");
	}

	private void ensureInstallDirectory()
	{
		if (!exists(root))
		{
			mkdirRecurse(root);
		}
		tmpRoot = buildPath(root, ".installer_tmp_" ~ randomString(6));
		mkdirRecurse(tmpRoot);
	}

	private string randomString(size_t length)
	{
		static immutable chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
		return chars.map!(a => a).array.randomSample(length).text;
	}

	void installCompiler(string compilerSpec)
	{
		log("Installing compiler: " ~ compilerSpec);
		auto resolvedCompiler = resolveLatestVersion(compilerSpec);

		auto downloadUrl = getCompilerDownloadUrl(resolvedCompiler);
		downloadAndExtract(downloadUrl, buildPath(root, resolvedCompiler));

		generateActivationScripts(resolvedCompiler);
	}

	private string resolveLatestVersion(string compilerSpec)
	{
		// If no specific version is provided, fetch the latest version
		if (compilerSpec.endsWith("latest") || compilerSpec.empty)
		{
			try
			{
				auto response = get("https://ldc-developers.github.io/LATEST");
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
				auto response = get("https://github.com/ldc-developers/ldc/commits/master.atom");
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

	private string getCompilerDownloadUrl(string compilerSpec)
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
					compilerVersion, compilerVersion, this.currentOS, this.currentArch, ext) : fmt(
					"https://github.com/ldc-developers/ldc/releases/download/CI/ldc2-%s-%s-%s%s",
					compilerVersion, this.currentOS, this.currentArch, ext);
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

	private void downloadAndExtract(string url, string targetPath)
	{
		if (!exists(targetPath ~ ext))
		{
			download(url, targetPath ~ ext);

			// Extract the downloaded archive
			version (Windows)
				extract7z(targetPath ~ ext, targetPath);
			else
				extractTarXZ(targetPath ~ ext, targetPath);

			log("Extracted compiler to " ~ targetPath);

			toolchainExtractPath = buildPath(targetPath, fmt("ldc2-%s-%s-%s", this.compilerVersion, this
					.currentOS.to!string, this
					.currentArch.to!string));
		}
		else
		{
			toolchainExtractPath = buildPath(targetPath, fmt("ldc2-%s-%s-%s", this.compilerVersion, this
					.currentOS.to!string, this
					.currentArch.to!string));

			log("Compiler already exists at " ~ toolchainExtractPath);
		}
	}

	private void extractTarXZ(string tarFile, string destination) @safe
	{
		log("Extracting TarXZ: " ~ tarFile);
		if (exists(destination))
			rmdirRecurse(destination);

		mkdirRecurse(destination);
		auto pid = spawnProcess([
			"tar", "xf", tarFile, fmt("--directory=%s", destination)
		]);
		enforce(pid.wait() == 0, "Extraction failed");
	}

	private void extractZip(string zipFile, string destination) @trusted
	{
		log("Extracting Zip: " ~ zipFile);
		ZipArchive archive = new ZipArchive(read(zipFile)); // unsafe/@system
		string prefix;

		if (exists(zipFile))
			std.file.remove(zipFile);

		if (exists(destination))
			rmdirRecurse(destination);

		mkdirRecurse(destination);

		foreach (name, _; archive.directory)
		{
			prefix = name[0 .. $ - name.find("/").length + 1];
			break;
		}
		foreach (name, am; archive.directory)
		{
			if (!am.expandedSize)
				continue;

			string path = buildPath(destination, chompPrefix(name, prefix));
			auto dir = dirName(path);
			if (!dir.empty && !dir.exists)
				mkdirRecurse(dir);
			archive.expand(am);
			std.file.write(path, am.expandedData);
		}
	}

	private void extract7z(string sevenZipFile, string destination) @trusted
	{

		log("Extracting 7z: " ~ sevenZipFile);

		if (exists(destination))
			rmdirRecurse(destination);

		mkdirRecurse(destination);

		auto pid = spawnProcess([
			"7z", "x", sevenZipFile, fmt("-o%s", destination)
		]);
		enforce(pid.wait() == 0, "7z extraction failed");
	}

	private void generateActivationScripts(string compilerName)
	{
		compilerPath = buildPath(root, compilerName);
		string scriptsDir = buildPath(compilerPath, "activation");
		mkdirRecurse(scriptsDir);

		// Bash activation script
		string bashScript = buildPath(scriptsDir, "activate.sh");
		std.file.write(bashScript, q"[#!/bin/bash
		export PATH="$PATH:COMPILER_PATH/bin"
		export DC_PATH=COMPILER_PATH
		]".replace("COMPILER_PATH", toolchainExtractPath));

		// Fish activation script
		string fishScript = buildPath(scriptsDir, "activate.fish");
		std.file.write(fishScript, q"[#!/usr/bin/env fish
		set -x PATH $PATH COMPILER_PATH/bin
		set -x DC_PATH COMPILER_PATH
		]".replace("COMPILER_PATH", toolchainExtractPath));

		// Windows batch script
		string batchScript = buildPath(scriptsDir, "activate.bat");
		std.file.write(batchScript, q"[@echo off
		set PATH=%PATH%;COMPILER_PATH\bin
		set DC_PATH=COMPILER_PATH
		]".replace("COMPILER_PATH", toolchainExtractPath));

		log("Generated activation scripts for " ~ compilerName);
	}

	void uninstallCompiler(string compilerName)
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

	string[] listInstalledCompilers()
	{
		log("Listing installed compilers");
		return dirEntries(root, SpanMode.shallow)
			.filter!(entry =>
					entry.isDir &&
					!entry.name.baseName.startsWith(".installer_tmp_")
		)
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

void main(string[] args)
{
	auto installer = new CompilerManager();
	bool verbose = false;

	if (args.length < 2 || args[1] == "--help" || args[1] == "-h")
	{
		writefln("Usage: %s [command] [options]", args[0]);
		writeln("Commands:");
		writeln("  install [compiler]   Install a D compiler (default: ldc2-latest)");
		writeln("  uninstall [compiler] Uninstall a specific compiler");
		writeln("  list                 List installed compilers");
		writeln("  --verbose            Enable verbose output");
		return;
	}
	else
	{
		if (canFind(args, "dmd") || canFind(args, "gdc"))
		{
			throw new Exception("Only ldc compilers are allowed.");
		}
	}
	if (canFind(args, "--verbose") || canFind(args, "-v"))
		installer.verbose = true;

	switch (args[1])
	{
	case "install":
		const compiler = args.filter!(arg => arg.startsWith("ldc2-")).empty ? "ldc2-latest" : args.filter!(
			arg => arg.startsWith("ldc2-")).front;
		installer.installCompiler(compiler);
		break;
	case "uninstall":
		installer.uninstallCompiler(args[2]);
		break;
	case "list":
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
