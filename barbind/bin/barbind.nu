#!/env nu

def main [
    profile: string,
    targetDir: string,
    outDir: string,
    --configDir (-c): string,
] {
    let configDir = getConfigDir $configDir;
    let profileData = getProfile $configDir $profile;
    let targetDir = $targetDir | path expand;
    let outDir = $outDir | path expand;
    for $dirPath in [$targetDir, $outDir] {
        if ($dirPath | path type) != dir {
            error make $"Directory does not exist: ($dirPath)";
        };
    };
}

def loadResource [resourceMap: record, directory: string, resource: string] -> record {
    if ($resourceMap.map.$)
    
    let filePath = {
        parent: ([$resourceMap.baseDir, $directory] | path join),
        stem: $resource,
        extension: 'toml',
    };

}

def getConfigDir [configDir?: string] -> string {
    if ($configDir != null) and (($configDir | path type) != dir) {
        error make $"Directory does not exist: ($configDir)";
    };
    let configDir = $configDir
        | default {
            [
                $"($env.XDG_CONFIG_HOME)/barbind",
                $"($env.HOME)/.config/barbind",
                "/etc/barbind"
            ] | where {($in | path type) == dir} | first;
        };
    if $configDir == null {
        error make "No valid default config directories found. Use --configDir option.";
    };
    return $configDir | path expand;
}

def getProfile [configDir: string, profilePath: string] -> record {
    let filePath = {
        parent: ([$configDir, "profiles"] | path join),
        stem: $profilePath,
        extension: 'toml'
    } | path join;
    if ($filePath | path type) != file {
        error make $"Profile '($profilePath)' does not exist \(expected file at ($filePath))";
    }
    return open $filePath| from toml
    | default {
        error make $"Could not parse profile file ($filePath)."
    };
}