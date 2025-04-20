module impl;

public import std;

enum OS
{
    alpine,
    android,
    freebsd,
    linux,
    osx,
    windows
}

enum Arch
{
    arm64,
    aarch64,
    armv7a,
    multilib,
    universal,
    x86_64,
    x64,
    x86,
}

enum Releases
{
    latest,
    beta,
    nightly,
}

class CompilerManager
{
    private
    {
        string root;
        string compilerPath;
        string toolchainExtractPath;
        string crossPlatform;
        string compilerVersion;
        version (Windows)
            immutable string ext = ".7z";
        else
            immutable string ext = ".tar.xz";
        OS currentOS;
        Arch currentArch;
        Releases rel;
    }
    bool verbose;

    this(string installRoot, string platform) @safe
    {
        if (!platform.empty)
            this.crossPlatform = platform.toLower;
        else if (!environment.get("LDC2_PLATFORM").empty)
            this.crossPlatform = environment.get("LDC2_PLATFORM").toLower;

        if (!installRoot.empty)
            environment["DC_PATH"] = installRoot;
        else if (environment.get("DC_PATH").empty)
            environment["DC_PATH"] = defaultInstallRoot();

        root = environment.get("DC_PATH");

        if (!exists(root))
            mkdir(root);

        verbose = false;
        detectPlatform();
    }

    private string defaultInstallRoot() const @safe
    {
        version (Windows)
            return buildPath(environment.get("LOCALAPPDATA", expandTilde("~")), "dlang");
        else version (Posix)
            return buildPath(environment.get("HOME", expandTilde("~")), ".dlang");
        else
            return expandTilde("~/dlang");
    }

    private void detectPlatform() @safe
    {
        if (!this.crossPlatform.empty)
        {
            if (this.crossPlatform.endsWith("x86_64"))
                this.currentArch = Arch.x86_64;
            else if (this.crossPlatform.endsWith("x64"))
                this.currentArch = Arch.x64;
            else if (this.crossPlatform.endsWith("x86"))
                this.currentArch = Arch.x86;
            else if (this.crossPlatform.endsWith("aarch64"))
                this.currentArch = Arch.aarch64;
            else if (this.crossPlatform.endsWith("arm64"))
                this.currentArch = Arch.arm64;
            else if (this.crossPlatform.endsWith("armv7a"))
                this.currentArch = Arch.armv7a;
            else if (this.crossPlatform.endsWith("multilib"))
                this.currentArch = Arch.multilib;
            else if (this.crossPlatform.endsWith("universal"))
                this.currentArch = Arch.universal;
            else
                enforce(0, "Unsupported architecture");

            if (this.crossPlatform.startsWith("alpine"))
                this.currentOS = OS.alpine;
            else if (this.crossPlatform.startsWith("android"))
                this.currentOS = OS.android;
            else if (this.crossPlatform.startsWith("freebsd"))
                this.currentOS = OS.freebsd;
            else if (this.crossPlatform.startsWith("linux"))
                this.currentOS = OS.linux;
            else if (this.crossPlatform.startsWith("osx"))
                this.currentOS = OS.osx;
            else if (this.crossPlatform.startsWith("windows"))
                this.currentOS = OS.windows;
            else
                enforce(0, "Unsupported platform");
        }
        else
        {
            version (X86_64)
                this.currentArch = Arch.x86_64;
            else version (ARM)
                this.currentArch = Arch.armv7a;
            else version (AArch64)
                this.currentArch = Arch.aarch64;
            else
                static assert(0, "Unsupported architecture");

            version (OSX)
            {
                this.currentOS = OS.osx;
                this.currentArch = Arch.universal;
            }
            else version (Android)
                this.currentOS = OS.android;
            else version (FreeBSD)
                this.currentOS = OS.freebsd;
            else version (linux)
            {
                version (CRuntime_Musl)
                    this.currentOS = OS.alpine;
                else
                    this.currentOS = OS.linux;
            }
            else version (Windows)
            {
                this.currentOS = OS.windows;
                this.currentArch = Arch.multilib;
            }
            else
                static assert(0, "Unsupported operating system");
        }
    }

    void installCompiler(string compilerSpec) @safe
    {
        if (compilerSpec.canFind("redub"))
            installRedub();
        else
        {
            writeln("Installing to " ~ root);
            log("Installing compiler: " ~ compilerSpec);
            immutable resolvedCompiler = resolveLatestVersion(compilerSpec);

            immutable downloadUrl = getCompilerDownloadUrl(resolvedCompiler);
            downloadAndExtract(downloadUrl, buildPath(root, resolvedCompiler));

            if (compilerSpec.canFind("opend"))
                compilerPath = buildPath(root, resolvedCompiler, fmt("opend-%s-%s-%s", this.compilerVersion, this
                        .currentOS, this
                        .currentArch), "bin");
            else
                compilerPath = buildPath(root, resolvedCompiler, fmt("ldc2-%s-%s-%s", this.compilerVersion, this
                        .currentOS, this
                        .currentArch), "bin");

            setEnvInstallPath();
            setPersistentEnv();
        }
    }

    void installRedub() @safe
    {
        string rootPath;
        if (!environment.get("LDC_PATH").empty)
            rootPath = environment.get("LDC_PATH");
        if (exists(compilerPath) || !compilerPath.empty)
            rootPath = compilerPath;

        if (rootPath.empty)
            enforce(0, "Missing installed compiler");

        writeln("Installing redub to " ~ rootPath);
        log("Installing redub build system");

        string redubUrl = "https://github.com/MrcSnm/redub/releases/latest/download";
        string redubFile;

        version (Windows)
            redubFile = fmt("redub-%s-latest-%s.exe", this.currentOS, this.currentArch);
        else version (FreeBSD)
            enforce(0, "Redub is not supported on FreeBSD");
        else version (Android)
            enforce(0, "Redub is not supported on Android");
        else version (linux)
        {
            version (AArch64)
                redubFile = "redub-ubuntu-24.04-arm-arm64";
            else
            {
                version (CRuntime_Musl)
                    redubFile = fmt("redub-%s-%s", this.currentOS, this.currentArch);
                else
                    redubFile = fmt("redub-ubuntu-latest-%s", this.currentArch);
            }
        }
        else version (OSX)
            redubFile = fmt("redub-%s-latest-%s", this.currentOS, this.currentArch);
        else
            static assert(0, "Unsupported operating system");

        version (FreeBSD)
        {
        }
        version (Android)
        {
        }
        else
        {
            redubUrl ~= "/" ~ redubFile;

            version (Windows)
                immutable string redubExe = buildPath(rootPath, "redub.exe");
            else
                immutable string redubExe = buildPath(rootPath, "redub");

            if (!exists(redubExe))
                download(redubUrl, redubExe);
            else
                log("Redub already installed");

            version (Posix)
            {
                // Make executable
                executeShell("chmod +x " ~ redubExe);
            }
        }
    }

    void runCompiler(ref string compilerSpec, ref string[] args) @safe
    {
        log("Running compiler: " ~ compilerSpec);
        compilerPath = findLDC2Path;
        if (args.length == 0)
        {
            throw new Exception("No flags provided for ldc2. Use 'run -- <flags>'.");
        }
        if (this.compilerPath.empty)
        {
            throw new Exception("Error: No LDC2 installation found.");
        }
        string[] cmd = [compilerPath] ~ args;
        auto result = execute(cmd);
        if (result.status != 0)
        {
            writeln("LDC2 execution failed with status ", result.status);
            writeln(result.output);
        }
        else
        {
            writeln(result.output);
        }
    }

    private string findLDC2Path(const size_t index = 0) @safe
    {
        // Check for installed compilers and return the path to ldc2 if found
        const string[] installed = listInstalledCompilers().filter!(
            ver => ver.startsWith("ldc2-")).array;

        enforce(!installed.empty, "No LDC2 installation found.");

        enforce(index < installed.length, fmt(
                "Invalid index %s; exceeds available installations.", index));

        immutable string ldc2Dir = buildPath(root, installed[index], format("ldc2-%s-%s-%s",
                installed[index]["ldc2-".length .. $], this.currentOS, this.currentArch), "bin");
        log("Looking for LDC2 installation at: " ~ ldc2Dir);

        version (Posix)
            immutable string ldc2Executable = buildPath(ldc2Dir, "ldc2");
        else version (Windows)
            immutable string ldc2Executable = buildPath(ldc2Dir, "ldc2.exe");

        if (exists(ldc2Executable))
        {
            log("Found LDC2 executable at: " ~ ldc2Executable);
            return ldc2Executable;
        }
        else
        {
            throw new Exception(format("LDC2 executable not found at %s", ldc2Executable));
        }
    }

    private void setEnvInstallPath() @safe
    {
        // Set the environment variable for add compilerPath into PATH
        version (Posix)
        {
            immutable string userShell = getDefaultUserShell();
            debug writefln("\nDetected default user shell: %s", userShell);
            immutable string homeDir = environment.get("HOME", "~");
            bool pathSet = false;

            // Check for shell configuration files
            string[] configFiles;
            if (userShell.endsWith("zsh"))
                configFiles = [".zshrc"];
            else if (userShell.endsWith("bash"))
                configFiles = [".bashrc", ".bash_profile"];
            else if (userShell.endsWith("fish"))
                configFiles = [".config/fish/config.fish"];
            else
                configFiles = [".profile"]; // Fallback for other shells

            foreach (file; configFiles)
            {
                immutable string configPath = buildPath(homeDir, file);
                if (exists(configPath))
                {
                    string currentPathContent = readText(configPath);
                    string ldcPathEntry = fmt("export LDC_PATH=%s", compilerPath);
                    string newPathEntry = userShell.endsWith("fish")
                        ? fmt("set -gx PATH $PATH $LDC_PATH\n") : fmt(
                            "export PATH=$PATH:$LDC_PATH\n");

                    // Remove existing entries and overwrite
                    string[] lines = currentPathContent.splitLines();

                    lines = lines.filter!(line =>
                            !line.canFind(compilerPath) &&
                            !line.canFind("LDC_PATH=") &&
                            !line.canFind("export PATH=$PATH:$LDC_PATH") &&
                            !line.canFind("set -gx PATH $PATH $LDC_PATH")).array;

                    lines ~= [ldcPathEntry, newPathEntry];

                    std.file.write(configPath, lines.join("\n") ~ "\n");
                    log("PATH updated in " ~ file ~ ". Changes will apply on next shell session start or after sourcing " ~ file ~ ".");

                    pathSet = true;
                    break; // Stop once we've updated or checked one file
                }
            }

            if (!pathSet)
            {
                log("No shell configuration file found. Please add the PATH manually or create one of the following files:
				.bashrc, .zshrc, .profile, .bash_profile, .config/fish/config.fish.");
                writefln("Manual command:\nexport PATH=%s:$PATH", compilerPath);
            }
        }
        else version (Windows)
        {
            immutable string command = fmt("powershell -Command \"$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User'); if (!$currentPath.Contains('%s')) { [Environment]::SetEnvironmentVariable('PATH', $currentPath + ';' + '%s', 'User') }\"", compilerPath, compilerPath);
            auto result = executeShell(command);
            enforce(result.status == 0, "Failed to set PATH: " ~ result.output);
            log("PATH updated in user environment.");
        }
    }

    private void removePathFromShellConfig() @safe
    {
        version (Posix)
        {
            immutable string userShell = getDefaultUserShell();
            immutable string homeDir = environment.get("HOME", "~");

            // Same config files as in setEnvInstallPath
            string[] configFiles;
            if (userShell.endsWith("zsh"))
                configFiles = [".zshrc"];
            else if (userShell.endsWith("bash"))
                configFiles = [".bashrc", ".bash_profile"];
            else if (userShell.endsWith("fish"))
                configFiles = [".config/fish/config.fish"];
            else
                configFiles = [".profile"];

            foreach (file; configFiles)
            {
                immutable string configPath = buildPath(homeDir, file);
                if (exists(configPath))
                {
                    string content = readText(configPath);
                    string[] lines = content.splitLines();

                    // Remove lines containing the compiler path or LDC-related entries
                    lines = lines.filter!(line =>
                            !line.canFind(compilerPath) &&
                            !line.canFind("LDC_PATH=") &&
                            !line.canFind("export PATH=$PATH:$LDC_PATH") &&
                            !line.canFind("set -gx PATH $PATH $LDC_PATH") &&
                            !line.canFind("LDC2_PLATFORM") &&
                            !line.canFind("LDC2_VERSION")
                    ).array;

                    // Write back the filtered content

                    std.file.write(configPath, lines.join("\n") ~ "\n");
                    log("Removed PATH and environment entries from " ~ file);
                }
            }
        }
        else version (Windows)
        {
            // Remove path from Windows user environment
            immutable string command = fmt("powershell -Command \"[Environment]::SetEnvironmentVariable('PATH', ([Environment]::GetEnvironmentVariable('PATH', 'User') -split ';' | Where-Object { $_ -ne '%s' }) -join ';', 'User')\"", compilerPath);
            auto result = executeShell(command);
            enforce(result.status == 0, "Failed to remove PATH: " ~ result.output);
            log("Removed PATH from user environment.");
        }
    }

    private void setPersistentEnv() @safe
    {
        version (Posix)
        {
            immutable string userShell = getDefaultUserShell();
            immutable string homeDir = environment.get("HOME", "~");

            string[] configFiles;
            if (userShell.endsWith("zsh"))
                configFiles = [".zshrc"];
            else if (userShell.endsWith("bash"))
                configFiles = [".bashrc", ".bash_profile"];
            else if (userShell.endsWith("fish"))
                configFiles = [".config/fish/config.fish"];
            else
                configFiles = [".profile"];

            foreach (file; configFiles)
            {
                immutable string configPath = buildPath(homeDir, file);
                if (exists(configPath))
                {
                    string content = readText(configPath);
                    string[] lines = content.splitLines();

                    string platformVar = userShell.endsWith("fish")

                        ? fmt("set -gx LDC2_PLATFORM %s-%s", this.currentOS, this.currentArch) : fmt(
                            "export LDC2_PLATFORM=%s-%s", this.currentOS, this.currentArch);

                    string versionVar = userShell.endsWith("fish")

                        ? fmt("set -gx LDC2_VERSION %s", this.compilerVersion) : fmt("export LDC2_VERSION=%s", this
                                .compilerVersion);

                    // Remove existing environment variables if they exist
                    lines = lines.filter!(line =>
                            !line.canFind("LDC2_PLATFORM") &&
                            !line.canFind("LDC2_VERSION")
                    ).array;

                    // Append new environment variables
                    lines ~= platformVar;
                    lines ~= versionVar;

                    std.file.write(configPath, lines.join("\n") ~ "\n");
                    log("Updated environment variables in " ~ file);
                    break;
                }
            }
        }
        else version (Windows)
        {
            immutable string platformValue = fmt("%s-%s", this.currentOS, this.currentArch);
            immutable string[] commands = [

                fmt("powershell -Command \"[Environment]::SetEnvironmentVariable('LDC2_PLATFORM', '%s', 'User')\"", platformValue),
                fmt("powershell -Command \"[Environment]::SetEnvironmentVariable('LDC2_VERSION', '%s', 'User')\"", this
                        .compilerVersion)
            ];

            foreach (cmd; commands)
            {
                auto result = executeShell(cmd);
                enforce(result.status == 0, "Failed to set environment variable: " ~ result.output);
            }
            log("Set persistent environment variables in Windows registry");
        }
    }

    private void removePersistentEnv() @safe
    {
        version (Posix)
        {
            immutable string userShell = getDefaultUserShell();
            immutable string homeDir = environment.get("HOME", "~");

            string[] configFiles;
            if (userShell.endsWith("zsh"))
                configFiles = [".zshrc"];
            else if (userShell.endsWith("bash"))
                configFiles = [".bashrc", ".bash_profile"];
            else if (userShell.endsWith("fish"))
                configFiles = [".config/fish/config.fish"];
            else
                configFiles = [".profile"];

            foreach (file; configFiles)
            {
                immutable string configPath = buildPath(homeDir, file);
                if (exists(configPath))
                {
                    string content = readText(configPath);
                    string[] lines = content.splitLines()
                        .filter!(line => !line.canFind("LDC2_PLATFORM") && !line.canFind(
                                "LDC2_VERSION"))
                        .array;
                    std.file.write(configPath, lines.join("\n") ~ "\n");
                    log("Removed environment variables from " ~ file);
                    break;
                }
            }
        }
        else version (Windows)
        {
            immutable string[] commands = [
                "powershell -Command \"[Environment]::SetEnvironmentVariable('LDC2_PLATFORM', $null, 'User')\"",
                "powershell -Command \"[Environment]::SetEnvironmentVariable('LDC2_VERSION', $null, 'User')\""
            ];

            foreach (cmd; commands)
            {
                auto result = executeShell(cmd);
                enforce(result.status == 0, "Failed to remove environment variable: " ~ result
                        .output);
            }
            log("Removed persistent environment variables from Windows registry");
        }
    }

    private string getDefaultUserShell() const @safe
    {
        try
        {
            version (FreeBSD)
            {
                auto result = execute([
                    "getent", "passwd", environment.get("USER", "root")
                ]);
                if (result.status == 0)
                {

                    string[] parts = result.output.split(":");
                    if (parts.length > 6)
                    {

                        return parts[6].strip();
                    }
                }
            }
            else version (linux)
            {
                auto result = execute([
                    "getent", "passwd", environment.get("USER", "root")
                ]);
                if (result.status == 0)
                {
                    string[] parts = result.output.split(":");
                    if (parts.length > 6)
                    {
                        return parts[6].strip();
                    }
                }
            }
            else version (OSX)
            {
                auto result = execute([
                    "dscl", ".", "-read", "/Users/" ~ environment["USER"],
                    "UserShell"
                ]);
                if (result.status == 0)
                {
                    string[] lines = result.output.splitLines();
                    foreach (line; lines)
                    {
                        if (line.startsWith("UserShell:"))
                        {
                            return line["UserShell:".length .. $].strip();
                        }
                    }
                }
            }
            log("Could not determine default shell. Using /bin/sh as fallback.");
            return "/bin/sh";
        }
        catch (Exception e)
        {
            writeln("Error getting user shell: " ~ e.msg);
            throw e;
        }
    }

    private string resolveLatestVersion(string compilerSpec) @trusted
    {
        // latest version is already specified
        if (compilerSpec.canFind("opend-latest"))
        {
            return compilerSpec;
        }
        // If no specific version is provided, fetch the latest version
        if (compilerSpec.endsWith("latest") || compilerSpec.empty)
        {
            scope (exit)
                this.rel = Releases.latest;
            try
            {
                auto response = get("https://ldc-developers.github.io/LATEST"); // @system
                immutable string latestVersion = strip(response.to!string);
                log("Resolved latest version: ldc2-" ~ latestVersion);
                return "ldc2-" ~ latestVersion;
            }
            catch (Exception e)
            {
                stderr.writeln("Error resolving latest version: " ~ e.msg);
                throw e;
            }
        }
        else if (compilerSpec.endsWith("beta"))
        {
            scope (exit)
                this.rel = Releases.beta;
            try
            {
                auto response = get("https://ldc-developers.github.io/LATEST_BETA"); // @system
                immutable string latestVersion = strip(response.to!string);
                log("Resolved latest beta version: ldc2-" ~ latestVersion);
                return "ldc2-" ~ latestVersion;
            }
            catch (Exception e)
            {
                stderr.writeln("Error resolving latest beta version: " ~ e.msg);
                throw e;
            }
        }
        else if (compilerSpec.endsWith("nightly") || compilerSpec.endsWith("master"))
        {
            scope (exit)
                this.rel = Releases.nightly;
            try
            {
                auto response = get(
                    "https://github.com/ldc-developers/ldc/commits/master.atom"); // @system
                auto commitHash = strip(response.split(
                        "<id>tag:github.com,2008:Grit::Commit/")[1].split("</id>")[0][0 .. 8]);
                stderr.writeln("Resolved nightly version: ldc2-" ~ commitHash.to!string);
                return "ldc2-" ~ commitHash.to!string;
            }
            catch (Exception e)
            {
                stderr.writeln("Error resolving nightly version: " ~ e.msg);
                throw e;
            }
        }
        // If a specific version is provided, return it
        return compilerSpec;
    }

    private string getCompilerDownloadUrl(string compilerSpec) @safe
    {
        string compilerVer = resolveLatestVersion(compilerSpec);

        if (compilerSpec.startsWith("ldc2-"))
        {
            compilerVersion = compilerVer["ldc2-".length .. $];
            log("Downloading LDC2 for version: " ~ compilerVersion);

            final switch (this.rel)
            {
            case Releases.latest:
                return fmt("https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s-%s%s",
                    compilerVersion, compilerVersion, this.currentOS, this.currentArch, this.ext);
            case Releases.nightly:
                return fmt("https://github.com/ldc-developers/ldc/releases/download/CI/ldc2-%s-%s-%s%s",
                    compilerVersion, this.currentOS, this.currentArch, this.ext);
            case Releases.beta:
                return fmt("https://github.com/ldc-developers/ldc/releases/download/v%s/ldc2-%s-%s-%s%s",
                    compilerVersion, compilerVersion, this.currentOS, this.currentArch, this.ext);
            }
        }
        if (compilerSpec.startsWith("opend-"))
        {
            // opend not have multilib support
            version (Windows)
                this.currentArch = Arch.x64;

            compilerVersion = compilerVer["opend-".length .. $];
            log("Downloading OpenD-LDC2 for version: " ~ compilerVersion);
            return fmt(
                "https://github.com/opendlang/opend/releases/download/CI/opend-%s-%s-%s%s",
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
            if (ext.endsWith("7z"))
                extract7z(targetPath ~ ext, targetPath);
            else
                extractTarXZ(targetPath ~ ext, targetPath);
            // Remove the downloaded tarball
            remove(targetPath ~ ext);

            log("Extracted compiler to " ~ targetPath);

            toolchainExtractPath = buildPath(targetPath, fmt("ldc2-%s-%s-%s", this.compilerVersion, this
                    .currentOS, this
                    .currentArch));

            writeln();
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

    void uninstallCompiler(string compilerName) @safe
    {
        log("Uninstalling compiler: " ~ compilerName);
        auto compilerPath = buildPath(root, compilerName);
        if (exists(compilerPath))
        {
            // Set compilerPath for PATH removal
            this.compilerPath = buildPath(compilerPath, fmt("ldc2-%s-%s-%s", compilerName["ldc2-".length .. $],
                    this.currentOS, this.currentArch), "bin");

            // Remove PATH entries first
            removePathFromShellConfig;
            removePersistentEnv;

            // Then remove the compiler directory
            rmdirRecurse(compilerPath);
            log("Successfully uninstalled " ~ compilerName);
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

    private JSONValue[] getGitHubList(string baseURL) const @trusted
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

    string[] listInstalledCompilers() const @trusted
    {
        log("Listing installed compilers");
        return dirEntries(root, SpanMode.shallow) // @system
            .filter!(entry => entry.isDir)
            .map!(entry => entry.name.baseName)
            .array;
    }

    private void log(string message) const @safe
    {
        if (verbose)
        {
            writeln(message);
        }
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
