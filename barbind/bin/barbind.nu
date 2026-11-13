#!/env nu

const selfDir = (path self | path expand | path dirname);
use ($selfDir | path join 'lib.nu') *;

# can set default config dir with env.BARBIND_CONFIG_DIR

def main [
    profile: string,
    read_dir: string,
    out_dir: string,
    --config-dir (-c): string,
    --verbose (-v): int = 0,
] {
    with-env {
        _BARBIND: {
            logClosure: (createLogClosure $verbose),
            barbindExtension: 'barbind',
        }
    } {
        let configDir: string = getConfigDir $config_dir;
        log 1 $"Using config directory: ($configDir)"
        let readDir: string = $read_dir | path expand;
        let outDir: string = $out_dir | path expand;
        for $dirPath in [$readDir, $outDir] {
            if ($dirPath | path type) != dir {
                error make {
                    msg: $"Directory does not exist: ($dirPath)"
                };
            };
        };
        let profile: record = loadProfile $configDir $profile;

        cd $readDir;
        let appliedProfile = applyProfile {baseDir: $configDir, map:{}} $profile;

        cd $outDir;
        $appliedProfile.writes
        | items {|k, v| {path: $k, text: $v} }
        | par-each {|write|
            let writePath = $write.path | path relative-to $readDir | stripBarbindExtension;
            mkdir ($writePath | path dirname);
            $write.text | save $writePath -f;
            $writePath | path expand
        }
        | sort
    }
}

def "main default-config-dir" []: nothing -> string {
    getConfigDir
}

def "main list all" [
    --config-dir (-c): string,
]: nothing -> record<profiles: table<name: string, file: string>, maps: table<name: string, file: string>, functions: table<name: string, file: string>, composites: table<name: string, file: string>> {
    {
        profiles: (main list profiles --config-dir=$config_dir),
        maps: (main list maps --config-dir=$config_dir),
        functions: (main list functions --config-dir=$config_dir),
        composites: (main list composites --config-dir=$config_dir),
    }
}

def "main list profiles" [
    --config-dir (-c): string,
]: nothing -> table<name: string, file: string> {
    listRegistry $config_dir $registryDirNames.profile '.toml'
}

def "main list maps" [
    --config-dir (-c): string,
]: nothing -> table<name: string, file: string> {
    listRegistry $config_dir $registryDirNames.map '.toml'
}

def "main list functions" [
    --config-dir (-c): string,
]: nothing -> table<name: string, file: string> {
    listRegistry $config_dir $registryDirNames.function
}

def "main list composites" [
    --config-dir (-c): string,
]: nothing -> table<name: string, file: string> {
    listRegistry $config_dir $registryDirNames.composite '.toml'
}