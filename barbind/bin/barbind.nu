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

def applyProfile [resourceRegistry: record<baseDir: string, map: record>, profile: record]: nothing -> record<registry: record<baseDir: string, writes: record>> {
    try {
        $profile.passes | reduce -f {
            writes: {},
            registry: $resourceRegistry
        } { |pass, acc|
            let passFilePaths: list<string> = $pass.files | each { glob $in -D } | flatten | uniq;
            let captureMap = $passFilePaths
            | each { |passFilePath|
                let captureSegments = try {
                    getCaptureSegments ($acc.writes | get $passFilePath -o | default (open $passFilePath -r)) $pass.capture;
                } catch { return null; };
                {
                    key: $passFilePath,
                    value: $captureSegments,
                }
            }
            | transpose -idr;
            let applied = applyLayers $acc.registry $captureMap $pass.layers;
            let writes = $applied.captureMap
            | items {|path, segments|
                {
                    key: $path,
                    value: ($segments | get text | str join),
                }
            }
            | transpose -idr;
            {
                registry: $applied.registry,
                writes: $writes,
            }
        }
    } catch {
        error make {
            msg: "Error while applying profile."
        };
    };    
}

def applyLayers [
    resourceRegistry: record<baseDir: string, map: record>,
    captureMap: record,
    layers: list<record>
]: nothing -> record<registry: record<baseDir: string, map: record>, captureMap: record> {
    mut operationMap: record = $captureMap
    | columns
    | each { {key: $in, value: []}}
    | transpose -idr;
    mut registry = $resourceRegistry;
    let capturePaths = $captureMap | columns;
    for $layer in $layers {
        let applyingPaths = if $layer.files != null { glob -D $layer.files | intersect $capturePaths } else { $capturePaths };
        for $applyingPath in $applyingPaths {
            let transformFetch = fetchTransformOperation $registry $layer.transform;
            $registry = $transformFetch.registry;
            $operationMap
            | upsert $applyingPath {append $transformFetch.operation};
        };
    };
    let operationMap = $operationMap;
    let registry = $registry;
    let appliedMap = $operationMap
    | items {|path, operations|
        let inputSegments = $captureMap | get $path -o;
        if $inputSegments == null { return null; }
        let outputSegments = $inputSegments
        | each {|segment|
            if $segment.isCaptured {
                $operations | reduce -f $segment.text {|operation, text| do $operation $text }
            } else {
                $segment.text;
            }
        };
        {
            $path: $path,
            value: $outputSegments,
        }
    }
    | transpose -idr;

    {
        registry: $registry,
        captureMap: $appliedMap,
    }
}

def getCaptureSegments [
    text: string, 
    capture: record<start: string, end: string, escape?: string>
]: nothing -> list<record<text:string, isCaptured:bool>> {
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
    --inheritChain: list<string> = [],
]: nothing -> record<registry: record<baseDir: string, map: record>, lookup: record> {
    if $mapName in $inheritChain {
        error make {
            msg: $"Map inheritance loop: ($inheritChain | append $mapName | str join ' -> ')"
        };
    };
    let registryDirectory = 'maps';
    let loaded = loadResource $resourceRegistry $registryDirectory $mapName;
    if $loaded.value.lookup != null {
        return {
            registry: $loaded.registry,
            lookup: $loaded.value.lookup,
        };
    };
    let data = $loaded.value.data;
    $data
    | get meta.inherit -o
    | default []
    | reduce -f {registry: $loaded.registry, lookup: {}} {|inherit, acc|
        let fetched = fetchMapLookup $acc.registry $inherit --inheritChain ($inheritChain | append $inherit);
        {
            registry: $fetched.registry,
            lookup: ($acc.lookup | merge $fetched.lookup),
        }
    }
    | update lookup {merge $data.map}
    | do {
        update registry {
            upsert (getRegistryResourcePath $registryDirectory $mapName).lookup $in.lookup
        }
    }
}

def fetchFunctionOperation [
    resourceRegistry: record<baseDir: string, map: record>,
    functionPath: string
]: nothing -> record<registry: record<baseDir: string, map: record>, operation: closure> {
    let registryDirectory = 'functions';
    {
        registry: $resourceRegistry,
        operation: {
            $in
            |^([$resourceRegistry.baseDir, $registryDirectory, $functionPath] | path join)
            | complete
            | get stdout
        },
    }
}

def fetchCompositeOperation [
    resourceRegistry: record<baseDir: string, map: record>,
    compositeName: string,
    --compositeChain: list<string> = [],
]: nothing -> record<registry: record<baseDir: string, map: record>, operation: record> {
    if $compositeName in $compositeChain {
        error make {
            msg: $"Composite reference loop: ($compositeChain | append $compositeName | str join ' -> ')"
        };
    };
    let registryDirectory = 'composites';
    let loaded = loadResource $resourceRegistry $registryDirectory $compositeName;
    if $loaded.value.operation != null {
        return {
            registry: $loaded.registry,
            operation: $loaded.value.operation,
        };
    };
    let sequence = $loaded.value.data.sequence;
    $sequence
    | reduce -f {registry: $loaded.registry, operation: {|x| $x}} {|transform, acc|
        let fetched = fetchTransformOperation $acc.registry $transform --compositeChain ($compositeChain | append $compositeName);
        {
            registry: $fetched.registry,
            operation: {do $fetched.operation (do $acc.operation $in)},
        }
    }
    | do {
        update registry {
            upsert (getRegistryResourcePath $registryDirectory $compositeName).operation $in.operation
        }
    }
}

def fetchTransformOperation [
    resourceRegistry: record<baseDir: string, map: record>,
    transform: record,
    --compositeChain: list<string> = [],
]: nothing -> record<registry: record<baseDir: string, map: record>, operation: record> {
    match $transform {
        {map: $mapName} => (
            let fetched = fetchMapLookup $resourceRegistry $mapName;
            {
                registry: $fetched.registry,
                operation: {|text|
                    $fetched.lookup | get $text -o | default $text;
                },
            }
        ),
        {function: $functionName} => (
            let fetched = fetchFunctionOperation $resourceRegistry $functionName;
            {
                registry: $fetched.registry,
                operation: $fetched.operation,
            }
        ),
        {composite: $compositeName} => (
            let fetched = fetchCompositeOperation $resourceRegistry $compositeName --compositeChain $compositeChain;
            {
                registry: $fetched.registry,
                operation: $fetched.operation,
            }
        ),
        _ => (error make {
            msg: $"Unknown transform type: ($transform)",
        }),
    }
}

def getRegistryResourcePath [
    directory: string,
    resource: string,
]: nothing -> cell-path {
    ['map', $directory, $resource] | into cell-path
}

def loadResource [
    resourceRegistry: record<baseDir: string, map: record>, 
    directory: string, 
    resource: string,
]: nothing -> record<registry: record<baseDir: string, map: record>, value: record<data: record>> {
    let resourcePath: cell-path = getRegistryResourcePath $directory $resource;
    let cached = $resourceRegistry | get $resourcePath -o;
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
    let registry = $resourceRegistry | upsert $resourcePath $value;
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
            msg: "No valid default config directories found. Use --configDir option."
        };
    };
    return $configDir | path expand;
}

def loadProfile [configDir: string, profilePath: string]: nothing -> record {
    let filePath = {
        parent: ([$configDir, "profiles"] | path join),
        stem: $profilePath,
        extension: 'toml',
    }
    | path join;

    if ($filePath | path type) != file {
        error make {
            msg: $"Profile '($profilePath)' does not exist \(expected file at ($filePath))"
        }
    };
    open $filePath
    | from toml
    | default {
        error make {
            msg: $"Could not parse profile file ($filePath)"
        }
    }
}