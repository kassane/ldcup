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

/// Convert a string to an enum value whose base type is string.
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

/// Strip a leading "v" from a version string (e.g. "v1.39.0" → "1.39.0").
private string stripLeadingV(string s) @safe pure
{
    return (s.length > 0 && s[0] == 'v') ? s[1 .. $] : s;
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
        // detectPlatform MUST run before defaultInstallRoot so currentOS is known.
        detectPlatform(platform.empty ? environment.get("LDC2_PLATFORM") : platform);

        root = installRoot.empty
            ? environment.get("LDC2_ROOTPATH", defaultInstallRoot()) : installRoot;

        if (!exists(root))
            mkdirRecurse(root);

        environment["LDC2_ROOTPATH"] = root;
        verbose = false;
    }

    string defaultInstallRoot() const @safe
    {
        string base = (currentOS == OS.windows)
            ? environment.get("LOCALAPPDATA", expandTilde("~")) : environment.get("HOME", expandTilde(
                    "~"));
        return buildPath(base, ".dlang");
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
            enforce(parts.length == 2, "Invalid platform format (expected OS-ARCH): " ~ platform);
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

        downloadAndExtract(downloadUrl, targetPath, resolvedCompiler.startsWith("opend-"));

        bool isOpend = compilerSpec.startsWith("opend-");
        string prefix = isOpend ? "opend" : "ldc2";
        compilerPath = buildPath(
            targetPath,
            format("%s-%s-%s-%s", prefix, compilerVersion, currentOS, currentArch),
            "bin"
        );

        setEnvInstallPath();
        setPersistentEnv();
    }

    void installRedub() @safe
    {
        auto rootPath = environment.get("LDC2_PATH", compilerPath);
        log("Installing redub to %s", rootPath);

        version (AArch64)
            currentArch = Arch.arm64;

        enforce(currentOS != OS.freebsd, "Redub is not supported on FreeBSD");
        enforce(currentOS != OS.android, "Redub is not supported on Android");

        string redubFile;
        if (currentOS == OS.windows)
            redubFile = format("redub-latest-%s-%s.exe", currentOS, currentArch);
        else if (currentOS == OS.osx || currentOS == OS.linux || currentOS == OS.alpine)
            redubFile = format("redub-latest-%s-%s", currentOS, currentArch);
        else
            throw new Exception("Unsupported OS for redub: %s".format(currentOS));

        auto redubUrl = "https://github.com/MrcSnm/redub/releases/download/nightly/" ~ redubFile;
        auto redubExe = buildPath(rootPath, (currentOS == OS.windows) ? "redub.exe" : "redub");

        if (!exists(redubExe))
        {
            download(redubUrl, redubExe);
            if (currentOS != OS.windows)
                executeShell("chmod +x " ~ redubExe);
        }
        else
            log("Redub already installed at %s", redubExe);
    }

    void runCompiler(string compilerSpec, string[] args) @safe
    {
        enforce(args.length > 0, "No flags provided. Use 'run -- <flags>'");
        log("Running compiler: %s", compilerSpec);
        compilerPath = findLDC2Path();
        enforce(!compilerPath.empty, "No LDC2 installation found");

        auto cmd = [compilerPath] ~ args;
        auto result = execute(cmd);
        writeln(result.output);
        enforce(result.status == 0, "LDC2 execution failed with status %d".format(result.status));
    }

    string findLDC2Path() @safe
    {
        auto installed = listInstalledCompilers().filter!(v => v.startsWith("ldc2-")).array;
        enforce(!installed.empty, "No LDC2 installation found in %s".format(root));

        string ver = installed[0]["ldc2-".length .. $];
        string ldc2Dir = buildPath(
            root, installed[0],
            format("ldc2-%s-%s-%s", ver, currentOS, currentArch),
            "bin"
        );
        auto ldc2Exe = buildPath(ldc2Dir, (currentOS == OS.windows) ? "ldc2.exe" : "ldc2");
        log("Checking for LDC2 at: %s", ldc2Exe);
        enforce(exists(ldc2Exe), "LDC2 executable not found at %s".format(ldc2Exe));
        return ldc2Exe;
    }

    void setEnvInstallPath() @safe
    {
        version (Posix)
        {
            immutable string userShell = getDefaultUserShell();
            immutable string homeDir = environment.get("HOME", "~");

            auto configFiles = shellConfigFiles(userShell, homeDir);
            bool pathSet = false;

            foreach (file; configFiles)
            {
                if (!exists(file))
                    continue;

                string content = readText(file);
                string[] lines = content.splitLines()
                    .filter!(l =>
                            !l.canFind("LDC2_PATH=") &&
                            !l.canFind("export PATH=$PATH:$LDC2_PATH") &&
                            !l.canFind("set -gx PATH $PATH $LDC2_PATH"))
                    .array;

                bool isFish = userShell.endsWith("fish");
                lines ~= format("export LDC2_PATH=%s", compilerPath);
                lines ~= isFish
                    ? "set -gx PATH $PATH $LDC2_PATH" : "export PATH=$PATH:$LDC2_PATH";

                std.file.write(file, lines.join("\n") ~ "\n");
                log("PATH updated in %s", file.baseName);
                pathSet = true;
                break;
            }

            if (!pathSet)
            {
                log("No shell configuration file found; please add PATH manually.");
                writefln("Manual command:\nexport PATH=%s:$PATH", compilerPath);
            }
        }
        else version (Windows)
        {
            immutable string cmd = format(
                `powershell -Command "$p = [Environment]::GetEnvironmentVariable('PATH','User'); ` ~
                    `if (!$p.Contains('%s')) { [Environment]::SetEnvironmentVariable('PATH', $p + ';' + '%s', 'User') }"`,
                compilerPath, compilerPath
            );
            auto result = executeShell(cmd);
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

            foreach (file; shellConfigFiles(userShell, homeDir))
            {
                if (!exists(file))
                    continue;
                string[] lines = readText(file).splitLines()
                    .filter!(l =>
                            !l.canFind(compilerPath) &&
                            !l.canFind("LDC2_PATH=") &&
                            !l.canFind("export PATH=$PATH:$LDC2_PATH") &&
                            !l.canFind("set -gx PATH $PATH $LDC2_PATH") &&
                            !l.canFind("LDC2_PLATFORM") &&
                            !l.canFind("LDC2_VERSION"))
                    .array;
                std.file.write(file, lines.join("\n") ~ "\n");
                log("Removed PATH and environment entries from %s", file.baseName);
            }
        }
        else version (Windows)
        {
            immutable string cmd = format(
                `powershell -Command "[Environment]::SetEnvironmentVariable('PATH',` ~
                    `([Environment]::GetEnvironmentVariable('PATH','User') -split ';' | ` ~
                    `Where-Object { $_ -ne '%s' }) -join ';', 'User')"`,
                compilerPath
            );
            auto result = executeShell(cmd);
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
            bool isFish = userShell.endsWith("fish");

            foreach (file; shellConfigFiles(userShell, homeDir))
            {
                if (!exists(file))
                    continue;

                string[] lines = readText(file).splitLines()
                    .filter!(l => !l.canFind("LDC2_PLATFORM") && !l.canFind("LDC2_VERSION"))
                    .array;

                lines ~= isFish
                    ? format("set -gx LDC2_PLATFORM %s-%s", currentOS, currentArch) : format(
                        "export LDC2_PLATFORM=%s-%s", currentOS, currentArch);
                lines ~= isFish
                    ? format("set -gx LDC2_VERSION %s", compilerVersion) : format(
                        "export LDC2_VERSION=%s", compilerVersion);

                std.file.write(file, lines.join("\n") ~ "\n");
                log("Updated environment variables in %s", file.baseName);
                break;
            }
        }
        else version (Windows)
        {
            immutable string platform = format("%s-%s", currentOS, currentArch);
            foreach (cmd; [
                format(`powershell -Command "[Environment]::SetEnvironmentVariable('LDC2_PLATFORM','%s','User')"`, platform),
                format(`powershell -Command "[Environment]::SetEnvironmentVariable('LDC2_VERSION','%s','User')"`, compilerVersion)
            ])
            {
                auto result = executeShell(cmd);
                enforce(result.status == 0, "Failed to set environment variable: " ~ result.output);
            }
            log("Set persistent environment variables in Windows registry.");
        }
    }

    private void removePersistentEnv() @safe
    {
        version (Posix)
        {
            immutable string userShell = getDefaultUserShell();
            immutable string homeDir = environment.get("HOME", "~");

            foreach (file; shellConfigFiles(userShell, homeDir))
            {
                if (!exists(file))
                    continue;
                string[] lines = readText(file).splitLines()
                    .filter!(l => !l.canFind("LDC2_PLATFORM") && !l.canFind("LDC2_VERSION"))
                    .array;
                std.file.write(file, lines.join("\n") ~ "\n");
                log("Removed environment variables from %s", file.baseName);
                break;
            }
        }
        else version (Windows)
        {
            foreach (cmd; [
                `powershell -Command "[Environment]::SetEnvironmentVariable('LDC2_PLATFORM',$null,'User')"`,
                `powershell -Command "[Environment]::SetEnvironmentVariable('LDC2_VERSION',$null,'User')"`
            ])
            {
                auto result = executeShell(cmd);
                enforce(result.status == 0, "Failed to remove environment variable: " ~ result
                        .output);
            }
            log("Removed persistent environment variables from Windows registry.");
        }
    }

    /// Returns the ordered list of shell config file full paths to check for the given shell.
    private string[] shellConfigFiles(string userShell, string homeDir) @safe pure
    {
        string[] files;
        if (userShell.endsWith("zsh"))
            files = [".zshrc"];
        else if (userShell.endsWith("bash"))
            files = [".bashrc", ".bash_profile"];
        else if (userShell.endsWith("fish"))
            files = [".config/fish/config.fish"];
        else
            files = [".profile"];
        return files.map!(f => buildPath(homeDir, f)).array;
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
                    "dscl", ".", "-read",
                    "/Users/" ~ environment.get("USER", ""),
                    "UserShell"
                ]);
                if (result.status == 0)
                    foreach (line; result.output.splitLines)
                        if (line.startsWith("UserShell:"))
                            return line["UserShell:".length .. $].strip;
            }
            log("Could not determine shell; using /bin/sh.");
            return "/bin/sh";
        }
        catch (Exception e)
        {
            throw new Exception("Error getting user shell: " ~ e.msg);
        }
    }

    string resolveVersion(string compilerSpec) @trusted
    {
        // opend-latest is fetched from the CI tag; no HTTP resolution needed.
        if (compilerSpec == "opend-latest")
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
        else // Explicit version — use as-is; normalise prefix if missing.
            return compilerSpec.startsWith("ldc2-") ? compilerSpec : "ldc2-" ~ compilerSpec;

        try
        {
            auto rq = Request();
            version (Windows)
                rq.sslSetCaCert(environment.get("CURL_CA_BUNDLE"));
            else
                rq.sslSetVerifyPeer(false);

            auto res = rq.get(url);
            enforce(res.code / 100 == 2,
                format("HTTP %d when resolving %s version", res.code, releaseType));

            string response = (cast(string) res.responseBody.data).strip;
            string dversion = (releaseType == ReleaseType.nightly)
                ? response.split("<id>tag:github.com,2008:Grit::Commit/")[1].split(
                    "</id>")[0][0 .. 8] : response;

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
        bool isOpend = compilerSpec.startsWith("opend-");
        string rawVersion = compilerSpec[isOpend ? "opend-".length: "ldc2-".length .. $];
        compilerVersion = stripLeadingV(rawVersion);

        log("Downloading %s version: %s",
            isOpend ? "OpenD" : "LDC2", compilerVersion);

        if (!isOpend)
        {
            string baseUrl = (releaseType == ReleaseType.nightly)
                ? "https://github.com/ldc-developers/ldc/releases/download/CI"
                : "https://github.com/ldc-developers/ldc/releases/download/v%s".format(
                    compilerVersion);
            return format("%s/ldc2-%s-%s-%s%s", baseUrl, compilerVersion, currentOS, currentArch, ext);
        }

        // opend
        Arch opendArch = (currentOS == OS.windows) ? Arch.x64 : currentArch;
        return format(
            "https://github.com/opendlang/opend/releases/download/CI/opend-%s-%s-%s%s",
            compilerVersion, currentOS, opendArch, ext
        );
    }

    private void download(string url, string fileName) @trusted
    {
        log("Downloading: %s", url);
        auto rq = Request();
        rq.useStreaming = true;
        version (Windows)
            rq.sslSetCaCert(environment.get("CURL_CA_BUNDLE"));
        else
            rq.sslSetVerifyPeer(false);

        auto res = rq.get(url);
        enforce(res.code / 100 == 2, format("HTTP %d while downloading %s", res.code, url));
        size_t contentLength = res.contentLength;

        auto file = File(fileName, "wb");
        size_t received = 0;
        enum barWidth = 50;

        foreach (ubyte[] data; res.receiveAsRange())
        {
            file.rawWrite(data);
            received += data.length;
            if (contentLength > 0)
            {
                float progress = cast(float) received / contentLength;
                int pos = cast(int)(barWidth * progress);
                write("\r[");
                foreach (i; 0 .. barWidth)
                    write(i < pos ? "=" : i == pos ? ">" : " ");
                writef("] %d%%", cast(int)(progress * 100));
                stdout.flush();
            }
        }
        writeln();
        file.close();
        log("Download complete: %s", fileName);
    }

    /// Download and extract a compiler archive into targetPath.
    /// isOpend controls whether the inner directory uses the "opend-" prefix.
    void downloadAndExtract(string url, string targetPath, bool isOpend = false) @safe
    {
        string prefix = isOpend ? "opend" : "ldc2";

        if (exists(targetPath))
        {
            toolchainExtractPath = buildPath(
                targetPath,
                format("%s-%s-%s-%s", prefix, compilerVersion, currentOS, currentArch)
            );
            log("Compiler already exists at %s", toolchainExtractPath);
            return;
        }

        string archive = targetPath ~ ext;
        download(url, archive);

        if (ext.endsWith("7z"))
            extract7z(archive, targetPath);
        else
            extractTarXZ(archive, targetPath);

        remove(archive);
        toolchainExtractPath = buildPath(
            targetPath,
            format("%s-%s-%s-%s", prefix, compilerVersion, currentOS, currentArch)
        );
        log("Extracted compiler to %s", targetPath);
    }

    void extractTarXZ(string tarFile, string destination) @safe
    {
        log("Extracting tar.xz: %s → %s", tarFile, destination);
        if (exists(destination))
            rmdirRecurse(destination);
        mkdirRecurse(destination);
        auto pid = spawnProcess([
            findProgram("tar"), "xf", tarFile, "--directory=" ~ destination
        ]);
        enforce(pid.wait == 0, "tar extraction failed for: " ~ tarFile);
    }

    void extract7z(string sevenZipFile, string destination) @safe
    {
        log("Extracting 7z: %s → %s", sevenZipFile, destination);
        if (exists(destination))
            rmdirRecurse(destination);
        mkdirRecurse(destination);
        auto pid = spawnProcess([
            findProgram("7z"), "x", sevenZipFile, "-o" ~ destination
        ]);
        enforce(pid.wait == 0, "7z extraction failed for: " ~ sevenZipFile);
    }

    void uninstallCompiler(string compilerName) @safe
    {
        log("Uninstalling %s", compilerName);
        auto targetPath = buildPath(root, compilerName);
        enforce(exists(targetPath), "Compiler not installed: " ~ compilerName);

        bool isOpend = compilerName.startsWith("opend-");
        string prefix = isOpend ? "opend" : "ldc2";
        string ver = compilerName[prefix.length + 1 .. $]; // skip "ldc2-" or "opend-"
        this.compilerPath = buildPath(
            targetPath,
            format("%s-%s-%s-%s", prefix, ver, currentOS, currentArch),
            "bin"
        );

        removePathFromShellConfig();
        removePersistentEnv();
        rmdirRecurse(targetPath);
        log("Uninstalled %s", compilerName);
    }

    void listLDCVersions() @safe
    {
        log("Fetching available LDC releases from GitHub…");
        auto results = getGitHubList("https://api.github.com/repos/ldc-developers/ldc/releases");
        foreach (tag; results.map!(r => r["tag_name"].str).array.sort)
            writeln(tag);
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

            auto res = rq.get(format("%s?per_page=100&page=%d", baseURL, page++));
            enforce(res.code / 100 == 2,
                format("HTTP %d when listing releases", res.code));

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
        log("Listing installed compilers in %s", root);
        return dirEntries(root, SpanMode.shallow)
            .filter!(e => e.isDir)
            .map!(e => e.name.baseName)
            .array
            .sort
            .release;
    }

    void log(Args...)(string fmt, Args args) @safe
    {
        if (verbose)
            writefln(fmt, args);
    }
}

string findProgram(string programName) @safe
{
    foreach (dir; environment.get("PATH", "").split(pathSeparator))
    {
        string fullPath = buildPath(dir, programName);
        version (Windows)
            fullPath ~= ".exe";
        if (exists(fullPath) && isFile(fullPath))
            return fullPath;
    }
    throw new Exception("Program not found in PATH: " ~ programName);
}
