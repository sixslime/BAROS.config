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

    const modifierLayers = [
        'meta',
        'alt',
        'control',
        'shift',
        'altgr',
    ];

    let axiom = {
        keyboard: {
            layout: (axiomPath 'keyboard' 'layout.toml' | open),
            aliases: (axiomPath 'keyboard' 'position_aliases.toml' | open),
        },
    };

    let layerModMap = $modifierLayers
    | each { { $in: [$in] } }
    | into record
    | merge ($axiom.keyboard.layout.layer
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
        | into record);

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
            | to toml;
        ),
        'maps/axiom/bindings/key_action.toml': (
            let map = $axiom.keyboard.aliases.keys | items {|alias, pos|
                let press = $axiom.keyboard.layout.main | get $pos -o | default $pos;
                if ($press | describe) != string {
                    error make {
                        msg: $"key alias '($alias)' points to key-pos '($pos)', which is bound to '($press)'; expected a direct key/string \(ex: 'j')",
                    }  
                } else {
                    { $alias: $press }
                }
            }
            | into record;
            {
                map: $map
            }
            | to toml;
        ),
        'maps/axiom/bindings/modifier.toml': (
            let map = $axiom.keyboard.aliases.modifiers | items {|alias, pos|
                let press = $axiom.keyboard.layout.main | get $pos -o | default $pos;
                let pressLayer = try { $press | get layer } catch {
                    error make {
                        msg: $"modifier alias '($alias)' points to key-pos '($pos)', which is bound to '($press)'; expected a modifier layer \(ex: { layer = 'meta' })",
                    }
                };
                let layerMods = $layerModMap | get $pressLayer -o | default {
                    error make {
                        msg: $"modifier alias '($alias)' points to key-pos '($pos)', which is bound to a layer that does not exist, '($pressLayer)'",
                    }
                };
                { $alias: ($layerMods | str join '+') }
            }
            | into record;
            {
                map: $map
            }
            | to toml;
        ),
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