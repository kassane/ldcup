module impl;

import requests;

public import std;

enum OS : string
{
    alpine = "alpine",
    android = "android",
    freebsd = "freebsd",
    linux = "linux",
    osx = "osx",
    windows = "windows"
}

enum Arch : string
{
    arm64 = "arm64",
    aarch64 = "aarch64",
    armv7a = "armv7a",
    multilib = "multilib",
    universal = "universal",
    x86_64 = "x86_64",
    x64 = "x64",
    x86 = "x86"
}

enum ReleaseType
{
    latest,
    beta,
    nightly
}

T fromString(T)(string s) @safe if (is(T == enum) && is(T : string))
{
    switch (s)
    {
        foreach (e; __traits(allMembers, T))
    case e:
            return __traits(getMember, T, e);
    default:
        throw new Exception("Unsupported %s: %s".format(T.stringof, s));
    }
}

class CompilerManager
{
private:
    string root;
    string compilerPath;
    string toolchainExtractPath;
    string compilerVersion;
    OS currentOS;
    Arch currentArch;
    ReleaseType releaseType;
    version (Windows)
        immutable string ext = ".7z";
    else
        immutable string ext = ".tar.xz";
public:
        bool verbose;

    this(string installRoot, string platform) @safe
    {
        root = installRoot.empty ? environment.get("LDC2_ROOTPATH", defaultInstallRoot)
            : installRoot;
        if (!exists(root))
            mkdirRecurse(root);
        environment["LDC2_ROOTPATH"] = root;

        detectPlatform(platform.empty ? environment.get("LDC2_PLATFORM") : platform);
        verbose = false;
    }

    string defaultInstallRoot() const @safe
    {
        return buildPath(environment.get((currentOS == OS.windows) ? "LOCALAPPDATA" : "HOME", expandTilde(
                "~")), ".dlang");
    }

    void detectPlatform(string platform) @safe
    {
        if (platform.empty)
        {
            version (X86_64)
                currentArch = Arch.x86_64;
            else version (ARM)
                currentArch = Arch.armv7a;
            else version (AArch64)
                currentArch = Arch.aarch64;
            else
                static assert(0, "Unsupported architecture");

            version (OSX)
            {
                currentOS = OS.osx;
                currentArch = Arch.universal;
            }
            else version (Android)
                currentOS = OS.android;
            else version (FreeBSD)
                currentOS = OS.freebsd;
            else version (linux)
            {
                version (CRuntime_Musl)
                    currentOS = OS.alpine;
                else
                    currentOS = OS.linux;
            }
            else version (Windows)
            {
                currentOS = OS.windows;
                currentArch = Arch.multilib;
            }
            else
                static assert(0, "Unsupported operating system");
        }
        else
        {
            auto parts = platform.toLower.split("-");
            enforce(parts.length == 2, "Invalid platform format: " ~ platform);
            currentOS = fromString!OS(parts[0]);
            currentArch = fromString!Arch(parts[1]);
        }
    }

    void installCompiler(string compilerSpec) @safe
    {
        if (compilerSpec.canFind("redub"))
            return installRedub();

        log("Installing %s to %s", compilerSpec, root);
        auto resolvedCompiler = resolveVersion(compilerSpec);
        auto downloadUrl = getCompilerDownloadUrl(resolvedCompiler);
        auto targetPath = buildPath(root, resolvedCompiler);

        downloadAndExtract(downloadUrl, targetPath);
        compilerPath = buildPath(targetPath, format("%s-%s-%s-%s", compilerSpec.startsWith("opend-") ? "opend" : "ldc2",
                compilerVersion, currentOS, currentArch), "bin");

        setEnvInstallPath();
        setPersistentEnv();
    }

    void installRedub() @safe
    {
        auto rootPath = environment.get("LDC2_PATH", compilerPath);
        log("Installing redub to %s", rootPath);

        version (AArch64)
            currentArch = Arch.arm64;

        string redubFile;
        if (currentOS == OS.freebsd)
            enforce(0, "Redub not supported on FreeBSD");
        else if (currentOS == OS.android)
            enforce(0, "Redub not supported on Android");
        else if (currentOS == OS.windows)
            redubFile = format("redub-latest-%s-%s.exe", currentOS, currentArch);
        else if (currentOS == OS.osx || currentOS == OS.linux || currentOS == OS.alpine)
            redubFile = format("redub-latest-%s-%s", currentOS, currentArch);
        else
            enforce(0, "Unsupported OS");

        auto redubUrl = "https://github.com/MrcSnm/redub/releases/download/nightly/" ~ redubFile;
        auto redubExe = buildPath(rootPath, (currentOS == OS.windows) ? "redub.exe" : "redub");

        if (!exists(redubExe))
        {
            download(redubUrl, redubExe);
            if (currentOS != OS.windows)
                executeShell("chmod +x " ~ redubExe);
        }
        else
            log("Redub already installed");
    }

    void runCompiler(string compilerSpec, string[] args) @safe
    {
        enforce(args.length > 0, "No flags provided. Use 'run -- <flags>'");
        log("Running compiler: %s", compilerSpec);
        compilerPath = findLDC2Path;
        enforce(!compilerPath.empty, "No LDC2 installation found");

        auto cmd = [compilerPath] ~ args;
        auto result = execute(cmd);
        writeln(result.output);
        enforce(result.status == 0, "LDC2 execution failed with status %s".format(result.status));
    }

    string findLDC2Path() @safe
    {
        auto installed = listInstalledCompilers().filter!(ver => ver.startsWith("ldc2-")).array;
        enforce(!installed.empty, "No LDC2 installation found");

        auto ldc2Dir = buildPath(root, installed[0], format("ldc2-%s-%s-%s", installed[0]["ldc2-".length .. $], currentOS, currentArch), "bin");
        auto ldc2Exe = buildPath(ldc2Dir, (currentOS == OS.windows) ? "ldc2.exe" : "ldc2");
        log("Checking for LDC2 at: %s", ldc2Exe);

        enforce(exists(ldc2Exe), "LDC2 executable not found at %s".format(ldc2Exe));
        return ldc2Exe;
    }

    void setEnvInstallPath() @safe
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
                    string ldcPathEntry = format("export LDC2_PATH=%s", compilerPath);
                    string newPathEntry = userShell.endsWith("fish")
                        ? format("set -gx PATH $PATH $LDC2_PATH\n") : format(
                            "export PATH=$PATH:$LDC2_PATH\n");

                    // Remove existing entries and overwrite
                    string[] lines = currentPathContent.splitLines();

                    lines = lines.filter!(line =>
                            !line.canFind(compilerPath) &&
                            !line.canFind("LDC2_PATH=") &&
                            !line.canFind("export PATH=$PATH:$LDC2_PATH") &&
                            !line.canFind("set -gx PATH $PATH $LDC2_PATH")).array;

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
            immutable string command = format("powershell -Command \"$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User'); if (!$currentPath.Contains('%s')) { [Environment]::SetEnvironmentVariable('PATH', $currentPath + ';' + '%s', 'User') }\"", compilerPath, compilerPath);
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
                            !line.canFind("LDC2_PATH=") &&
                            !line.canFind("export PATH=$PATH:$LDC2_PATH") &&
                            !line.canFind("set -gx PATH $PATH $LDC2_PATH") &&
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
            immutable string command = format("powershell -Command \"[Environment]::SetEnvironmentVariable('PATH', ([Environment]::GetEnvironmentVariable('PATH', 'User') -split ';' | Where-Object { $_ -ne '%s' }) -join ';', 'User')\"", compilerPath);
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

                        ? format("set -gx LDC2_PLATFORM %s-%s", this.currentOS, this.currentArch) : format(
                            "export LDC2_PLATFORM=%s-%s", this.currentOS, this.currentArch);

                    string versionVar = userShell.endsWith("fish")

                        ? format("set -gx LDC2_VERSION %s", this.compilerVersion) : format("export LDC2_VERSION=%s", this
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
            immutable string platformValue = format("%s-%s", this.currentOS, this.currentArch);
            immutable string[] commands = [

                format("powershell -Command \"[Environment]::SetEnvironmentVariable('LDC2_PLATFORM', '%s', 'User')\"", platformValue),
                format("powershell -Command \"[Environment]::SetEnvironmentVariable('LDC2_VERSION', '%s', 'User')\"", this
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
                    std.file.write(configPath, lines.join("\n"));
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

    string getDefaultUserShell() @safe
    {
        try
        {
            if (currentOS == OS.freebsd || currentOS == OS.linux || currentOS == OS.alpine)
            {
                auto result = execute([
                    "getent", "passwd", environment.get("USER", "root")
                ]);
                if (result.status == 0)
                {
                    auto parts = result.output.split(":");
                    if (parts.length > 6)
                        return parts[6].strip;
                }
            }
            else if (currentOS == OS.osx)
            {
                auto result = execute([
                    "dscl", ".", "-read", "/Users/" ~ environment["USER"],
                    "UserShell"
                ]);
                if (result.status == 0)
                    foreach (line; result.output.splitLines)
                        if (line.startsWith("UserShell:"))
                            return line["UserShell:".length .. $].strip;
            }
            log("Could not determine shell. Using /bin/sh");
            return "/bin/sh";
        }
        catch (Exception e)
        {
            throw new Exception("Error getting user shell: " ~ e.msg);
        }
    }

    string resolveVersion(string compilerSpec) @trusted
    {
        if (compilerSpec.canFind("opend-latest"))
            return compilerSpec;

        string url;
        if (compilerSpec.endsWith("latest") || compilerSpec.empty)
        {
            releaseType = ReleaseType.latest;
            url = "https://ldc-developers.github.io/LATEST";
        }
        else if (compilerSpec.endsWith("beta"))
        {
            releaseType = ReleaseType.beta;
            url = "https://ldc-developers.github.io/LATEST_BETA";
        }
        else if (compilerSpec.endsWith("nightly") || compilerSpec.endsWith("master"))
        {
            releaseType = ReleaseType.nightly;
            url = "https://github.com/ldc-developers/ldc/commits/master.atom";
        }
        else
            return compilerSpec;

        try
        {
            auto rq = Request();
            version (Windows)
                rq.sslSetCaCert(environment.get("CURL_CA_BUNDLE"));
            else
                rq.sslSetVerifyPeer(false);
            auto res = rq.get(url);
            enforce(res.code / 100 == 2, format("HTTP request returned status code %s", res.code));
            string response = cast(string) res.responseBody.data;
            string dversion = releaseType == ReleaseType.nightly ?
                response.split("<id>tag:github.com,2008:Grit::Commit/")[1].split(
                    "</id>")[0][0 .. 8].to!string : response.strip;
            log("Resolved %s version: ldc2-%s", releaseType, dversion);
            return "ldc2-" ~ dversion;
        }
        catch (Exception e)
        {
            throw new Exception("Error resolving %s version: %s".format(releaseType, e.msg));
        }
    }

    string getCompilerDownloadUrl(string compilerSpec) @safe
    {
        compilerVersion = compilerSpec[compilerSpec.startsWith("opend-") ? "opend-".length: "ldc2-".length .. $];
        log("Downloading %s for version: %s", compilerSpec.startsWith("opend-") ? "OpenD-LDC2" : "LDC2", compilerVersion);

        if (compilerSpec.startsWith("ldc2-"))
        {
            auto baseUrl = releaseType == ReleaseType.nightly ?
                "https://github.com/ldc-developers/ldc/releases/download/CI"
                : "https://github.com/ldc-developers/ldc/releases/download/v%s".format(
                    compilerVersion);
            return format("%s/ldc2-%s-%s-%s%s", baseUrl, compilerVersion, currentOS, currentArch, ext);
        }
        if (compilerSpec.startsWith("opend-"))
        {
            if (currentOS == OS.windows)
                currentArch = Arch.x64;
            return format("https://github.com/opendlang/opend/releases/download/CI/opend-%s-%s-%s%s",
                compilerVersion, currentOS, currentArch, ext);
        }
        throw new Exception("Unknown compiler: %s".format(compilerSpec));
    }

    private void download(string url, string fileName) @trusted
    {
        log("Downloading from URL: " ~ url);
        auto rq = Request();
        rq.useStreaming = true;
        version (Windows)
            rq.sslSetCaCert(environment.get("CURL_CA_BUNDLE"));
        else
            rq.sslSetVerifyPeer(false);
        auto res = rq.get(url);
        enforce(res.code / 100 == 2, format("HTTP request returned status code %s", res.code));
        size_t contentLength = res.contentLength;

        auto file = File(fileName, "wb");
        size_t received = 0;
        int barWidth = 50;

        foreach (ubyte[] data; res.receiveAsRange())
        {
            file.rawWrite(data);
            received += data.length;
            if (contentLength > 0)
            {
                float progress = cast(float) received / contentLength;
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
        }
        writeln();
        log("Download complete");
    }

    void downloadAndExtract(string url, string targetPath) @safe
    {
        if (exists(targetPath))
        {
            toolchainExtractPath = buildPath(targetPath, format("ldc2-%s-%s-%s", compilerVersion, currentOS, currentArch));
            log("Compiler already exists at %s", toolchainExtractPath);
            return;
        }

        download(url, targetPath ~ ext);
        if (ext.endsWith("7z"))
            extract7z(targetPath ~ ext, targetPath);
        else
            extractTarXZ(targetPath ~ ext, targetPath);
        remove(targetPath ~ ext);
        toolchainExtractPath = buildPath(targetPath, format("ldc2-%s-%s-%s", compilerVersion, currentOS, currentArch));
        log("Extracted compiler to %s", targetPath);
    }

    void extractTarXZ(string tarFile, ref string destination) @safe
    {
        log("Extracting TarXZ: %s", tarFile);
        if (exists(destination))
            rmdirRecurse(destination);
        mkdirRecurse(destination);
        auto pid = spawnProcess([
            findProgram("tar"), "xf", tarFile, "--directory=" ~ destination
        ]);
        enforce(pid.wait == 0, "TarXZ extraction failed");
    }

    void extract7z(string sevenZipFile, ref string destination) @safe
    {
        log("Extracting 7z: %s", sevenZipFile);
        if (exists(destination))
            rmdirRecurse(destination);
        mkdirRecurse(destination);
        auto pid = spawnProcess([
            findProgram("7z"), "x", sevenZipFile, "-o" ~ destination
        ]);
        enforce(pid.wait == 0, "7z extraction failed");
    }

    void uninstallCompiler(ref string compilerName) @safe
    {
        log("Uninstalling %s", compilerName);
        auto compilerPath = buildPath(root, compilerName);
        enforce(exists(compilerPath), "Compiler not installed: %s".format(compilerName));

        this.compilerPath = buildPath(compilerPath, format("ldc2-%s-%s-%s", compilerName["ldc2-".length .. $], currentOS, currentArch), "bin");
        removePathFromShellConfig;
        removePersistentEnv;
        rmdirRecurse(compilerPath);
        log("Uninstalled %s", compilerName);
    }

    void listLDCVersions() @safe
    {
        log("Listing LDC versions");
        auto results = getGitHubList("https://api.github.com/repos/ldc-developers/ldc/releases");
        writeln(results.map!(r => r["tag_name"].str)
                .array
                .sort
                .to!string);
    }

    JSONValue[] getGitHubList(string baseURL) @trusted
    {
        JSONValue[] results;
        int page = 1;
        while (true)
        {
            auto rq = Request();
            version (Windows)
                rq.sslSetCaCert(environment.get("CURL_CA_BUNDLE"));
            else
                rq.sslSetVerifyPeer(false);
            auto res = rq.get(format("%s?per_page=100&page=%s", baseURL, page++));
            enforce(res.code / 100 == 2, format("HTTP request returned status code %s", res.code));
            auto json = parseJSON(cast(string) res.responseBody.data).array;
            if (json.empty)
                break;
            results ~= json;
            if (json.length < 100)
                break;
        }

        return results;
    }

    string[] listInstalledCompilers() @trusted
    {
        log("Listing installed compilers");
        return dirEntries(root, SpanMode.shallow).filter!(e => e.isDir)
            .map!(e => e.name.baseName)
            .array;
    }

    void log(Args...)(string fmt, Args args) @safe
    {
        if (verbose)
            writefln(fmt, args);
    }
}

string findProgram(string programName) @safe
{
    foreach (path; environment.get("PATH").split(pathSeparator))
    {
        auto fullPath = buildPath(path, programName);
        version (Windows)
            fullPath ~= ".exe";
        if (exists(fullPath) && isFile(fullPath))
            return fullPath;
    }
    throw new Exception("Program not found: %s".format(programName));
}
