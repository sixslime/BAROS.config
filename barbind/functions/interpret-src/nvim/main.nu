#!/env nu

use $"(path self)/..../lib/axiom.nu" [
    parseBinding
];

def main [capture: string] {
    print -n ($capture | transform);
}

const modMap = {
    shift: 'S',
    control: 'C',
    meta: 'D',
    # alt/altgr A/M are read as the same in nvim.
    alt: 'A',
    altgr: 'M',
};

let specialKeyMap = [
    'space',
    'enter',
    'tab',
    'esc',
    'up',
    'down',
    'left',
    'right',
    'insert',
]
| append (1..12 | each { $"f($in)" })
| each { { $in: ($in | str capitalize) } }
| into record
| merge {
    backspace: 'BS',
    delete: 'Del',
    '<': 'lt',
    '\': 'Bslash',
    '|': 'Bar',
};

# because keys will be quoted in lua, need to escape '"'
const escapeMap = {
    '"': '\'
}

def transform []: string -> string {
    let binding = $in | parseBinding;
    let specialKey = $specialKeyMap | get $binding.key -o;
    let doAngleBrackets = ($binding.modifiers | is-not-empty) or ($specialKey | is-not-empty);
    let key = $specialKey | default {
        let escapeChar = $escapeMap | get $binding.key -o;
        $"($escapeChar)($binding.key)"
    };
    let bindBody = if ($binding.modifiers | is-not-empty) {
        let modStr = $binding.modifiers
        | each { $modMap | get $in -o }
        | str join '-';
        $"($modStr)-($key)"
    } else { $key };
    if $doAngleBrackets {
        $"<($bindBody)>"
    } else {
        $bindBody
    }
}