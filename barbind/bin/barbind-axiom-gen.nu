#!/env nu

def main [
    --config-dir (-c): string
]: nothing -> list<string> {
    let configDir = $config_dir | default { ^barbind default-config-dir };
    if ($configDir | path type) != dir {
        error make {
            msg: $"config dir specified ($configDir) is not a directory"
        }
    };

    const modifierNames = [
        'meta',
        'alt',
        'control',
        'shift',
        'altgr',
    ];
    const modifierSeparator = '&';
    const shiftLayerName = 'shift'

    let alphabetShiftMap = 'abcdefghijklmnopqrstuvwxyz'
    | split chars
    | each {
        { $in: ($in | str uppercase) }
    }
    | into record;

    let axiom = {
        keyboard: {
            layout: (axiomPath 'keyboard' 'layout.toml' | open),
            aliases: (axiomPath 'keyboard' 'position_aliases.toml' | open),
        },
    };

    let layerModMap = $modifierNames
    | each { { $in: [$in] } }
    | into record
    | merge (
        $axiom.keyboard.layout.layer?
        | default {}
        | columns
        | each {
            match ($in | split row '--' -n 2) {
                [$layer] => { $layer: [] },
                [$layer, $modsStr] => {
                    $layer: ($modsStr | split row '+'),
                },
                _ => null,
            }
        }
        | into record
    );

    let layerValueMap = $axiom.keyboard.layout.layer?
    | default {}
    | items {|rawName, layerMap|
        let layerName = $rawName
        | split column '--' name _
        | first
        | get name;
        { $layerName: $layerMap }
    }
    | into record;

    let writes = {
        'maps/axiom/bindings/key_pos.toml': (
            let map = $axiom.keyboard.layout.main | items {|pos, press|
                if ($press | describe) != string { null } else {
                    { $pos: $press }
                }
            }
            | where $in != null
            | into record;
            {
                map: $map
            }
            | to toml
        ),
        'maps/axiom/bindings/modifier_pos.toml': (
            let map = $axiom.keyboard.layout.main | items {|pos, press|
                try { $press | get layer } catch { null }
                | if ($in | is-not-empty) {
                    let pressLayer = $in;
                    let layerMods = $layerModMap | get $pressLayer -o | default -e {
                        error make {
                            msg: $"key-pos '($pos)' activates layer '($pressLayer)', which either does not exist or does not have any modifiers."
                        }
                    };
                    { $pos: ($layerMods | str join $modifierSeparator) }
                }
            }
            | where $in != null
            | into record;
            {
                map: $map
            }
            | to toml
        ),
        'maps/axiom/bindings/key_alias.toml': (
            let map = $axiom.keyboard.aliases.keys | items {|alias, pos|
                if ($pos | describe) != string {
                    error make {
                        msg: $"expected a string value for key alias '($alias)', got '($pos)'",
                    }  
                };
                { $alias: $pos }
            }
            | into record;
            {
                map: $map
            }
            | to toml
        ),
        'maps/axiom/bindings/modifier_alias.toml': (
            let map = $axiom.keyboard.aliases.modifiers | items {|alias, pos|
                if ($pos | describe) != string {
                    error make {
                        msg: $"expected a string value for modifier alias '($alias)', got '($pos)'",
                    }  
                };
                if ($axiom.keyboard.layout.main | get $pos -o | default {} | get layer -o | is-empty) {
                    error make {
                        msg: $"modifier aliases must point to explicitly-bound layer keys, '($alias)' points to key pos '$($pos)', which is not explicitly bound to a layer.",
                    }
                };
                { $alias: $pos }
            }
            | into record;
            {
                map: $map
            }
            | to toml
        ),
        'maps/axiom/bindings/shift_pos.toml': (
            let explicitShiftMap = $layerValueMap
            | get $shiftLayerName -o
            | default {}
            | items {|pos, press|
                if ($press | describe) != string { null } else {
                    { $pos: $press }
                }
            }
            | where $in != null
            | into record;
            let map = $alphabetShiftMap | merge $explicitShiftMap;
            {
                map: $map,
            }
            | to toml
        )
    };

    cd $configDir;
    $writes | items {|k, v| { path: ($k | path expand), content: $v } }
    | par-each {
        let write = $in;
        mkdir ($write.path | path dirname);
        $write.content | save -f $write.path;
        $write.path
    }
    | sort
}

def axiomPath [...path: string]: nothing -> string {
    ['/etc/nixos/axioms'] | append $path | path join
}