#!/env nu

def main [
    profile: string,
    targetDir: string,
    outDir: string,
    --configDir (-c): string,
] {
    let configDir: string = getConfigDir $configDir;
    let targetDir: string = $targetDir | path expand;
    let outDir: string = $outDir | path expand;
    for $dirPath in [$targetDir, $outDir] {
        if ($dirPath | path type) != dir {
            error make {
                msg: $"Directory does not exist: ($dirPath)"
            };
        };
    };
    let profile: record = loadProfile $configDir $profile;
    mut resourceRegistry: record<baseDir: string, map: record> = {baseDir: $configDir, map:{}};
    mut fileMap = {};
}

def applyProfile [resourceRegistry: record<baseDir: string, map: record>, profile: record] -> record<registry: record<baseDir: string, map: record>> {
    try {
        let writes: record = $profile.passes | reduce -f {
            pastWrites: {},
            registry: $resourceRegistry
        } { |pass, data|
            let passFilePaths: list<string> = $pass.files | each { glob $in -D } | flatten | uniq;
            let captureMap = $passFilePaths
            | each { |passFilePath|
                let captureSegments = try {
                    getCaptureSegments ($data.pastWrites | get $passFilePath -o | default (open $passFilePath -r)) $pass.capture;
                } catch { return null; };
                {
                    path: $passFilePath,
                    segments: $captureSegments,
                }
            }
            | transpose -idr;
            for $layer in $pass.layers {

            }
        };
    } catch {
        error make {
            msg: "Error while applying profile."
        };
    };    
}

def applyLayers [
    resourceRegistry: record<baseDir: string, map: record>,
    captureMap: record, layers: list<record>
] -> record<registry: record<baseDir: string, map: record>, captureMap: record> {
    mut layerPathMap: record = {};
    for $layer in $layers {
        let layerPaths = if $layer.files != null { glob -D $layer.files | intersect ($captureMap) | columns} else {$captureMap | columns};
        for $layerPath in $layerPaths {
            $layerPathMap | upsert $layerPath {default [] | append $layer};
        };
    };
    $layerPathMap
    | items {|path, applyingLayers|
        let readSegments = $captureMap | get $path -o;
        if $readSegments == null { return null; }
        let segments = $readSegments
        | each {|segment|
            if not $segment.isCaptured { return $segment };
            $applyingLayers
            | reduce -f $segment.text {
                
            };
        };
    };
}

def getCaptureSegments [
    text: string, 
    capture: record<start: string, end: string, escape?: string>
]: nothing -> list<record<text:string, isCaptured:bool>>? {
    try {
        mut textBuffer: string = $text;
        mut segments: list<record<isCaptured:bool, text:string>> = [];
        mut captureStarted = false;
        mut noRemainingEscapes = false;
        let lengths = {
            escape: (if $capture.escape != null {
                $capture.escape | str length -g;
            } else {
                0
            }),
            start: ($capture.start | str length -g),
            end: ($capture.end | str length -g),
        };
        loop {
            let nextIndexOf = {
                escape: (if ($noRemainingEscapes == false) and ($capture.escape != null) {
                    $textBuffer | str index-of $capture.escape -g
                } else {
                    $noRemainingEscapes = true;
                    -1
                }),
                capture: ($textBuffer | str index-of -g (if $captureStarted {
                    $capture.end
                } else {
                    $capture.start
                })),
            };
            if $nextIndexOf.capture == -1 {
                $segments = $segments | append {
                    text: ($textBuffer | str replace -a $capture.escape ''),
                    isCaptured: false,
                };
                break;
            };
            if ($nextIndexOf.escape != -1) and ($nextIndexOf.escape < $nextIndexOf.capture) {
                let escapedCharIndex = ($nextIndexOf.escape + $lengths.escape);
                let segmentText = [
                    ($textBuffer | str substring -g ..($nextIndexOf.escape - 1)),
                    ($textBuffer | str substring -g $escapedCharIndex..$escapedCharIndex),
                ] | str join;
                $segments = $segments | append {
                    text: $segmentText,
                    isCaptured: false,
                };
                $textBuffer = $textBuffer | str substring -g ($escapedCharIndex + 1)..;
                continue;
            };
            if $captureStarted {
                let capturedText = $textBuffer | str substring -g ($lengths.start)..($nextIndexOf.capture - 1);
                let continueIndex = ($nextIndexOf.capture + $lengths.end);
                $segments = $segments | append {
                    text: $capturedText,
                    isCaptured: true,
                };
                $textBuffer = $textBuffer | str substring -g ($continueIndex)..;
                $captureStarted = false;
            } else {
                $captureStarted = true;
            };
        };
    }
}
def fetchMapLookup [
    resourceRegistry: record<baseDir: string, map: record>, 
    mapName: string,
    --inheritSeen: list<string> = [],
]: nothing -> record<registry: record<baseDir: string, map: record>, value: record> {
    if $mapName in $inheritSeen {
        error make {
            msg: $"Map inheritance loop: ($inheritSeen | append $mapName | str join ' -> ')"
        };
    };
    let mapsDirectory = 'maps';
    let loaded = loadResource $resourceRegistry $mapsDirectory $mapName;
    if $loaded.value.lookup != null {
        return {
            registry: $loaded.registry,
            lookup: $loaded.value.lookup,
        };
    };
    let data = $loaded.data;
    let lookup = $data
    | get meta.inherit -o 
    | default []
    | reduce -f {registry: $loaded.registry, lookup: {}} {|inherit, acc|
        let fetched = fetchMapLookup $acc.registry $inherit --inheritSeen ($inheritSeen | append $inherit);
        {
            registry: $fetched.registry,
            lookup: $acc.lookup | merge $fetched.lookup;
        };
    };
    | merge $data.map;

}
def fetchFunctionOperation [
    resourceRegistry: record<baseDir: string, map: record>,
    mapName: string
]: nothing -> record<registry: record<baseDir: string, map: record>, operation: record> {
    return (loadResource $resourceRegistry 'maps' $mapName);
}
def loadResource [
    resourceRegistry: record<baseDir: string, map: record>, 
    directory: string, 
    resource: string,
]: nothing -> record<registry: record<baseDir: string, map: record>, value: record<data: record>> {
    let mapPath = ['map', $directory, $resource] | into cell-path;
    let cached = $resourceRegistry | get $mapPath -o;
    if $cached != null {
        return {
            registry: $resourceRegistry,
            value: $cached,
        };
    };
    let filePath = {
        parent: ([$resourceRegistry.baseDir, $directory] | path join),
        stem: $resource,
        extension: 'toml',
    };
    
    let data = try { open $filePath };
    catch { error make $"'($resource)' in ($directory) \(($filePath)) could not be opened."}
        | from toml;
    let value = {
        data: $data,
    };
    let registry = $resourceRegistry | upsert $mapPath $value;
    return {
        registry: $registry,
        value: $value,
    };
}

def getConfigDir [configDir?: string]: nothing -> string {
    if ($configDir != null) and (($configDir | path type) != dir) {
        error make {
            msg: $"Directory does not exist: ($configDir)"
        };
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
        error make {
            msg: "No valid default config directories found. Use --configDir option.";
        };
    };
    return $configDir | path expand;
}

def loadProfile [configDir: string, profilePath: string]: nothing -> record {
    let filePath = {
        parent: ([$configDir, "profiles"] | path join),
        stem: $profilePath,
        extension: 'toml'
    } | path join;

    if ($filePath | path type) != file {
        error make {
            msg: $"Profile '($profilePath)' does not exist \(expected file at ($filePath))"
        };
    }
    return (open $filePath | from toml
    | default {
        error make {
            msg: $"Could not parse profile file ($filePath)."
        };
    });
}