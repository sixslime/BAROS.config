
export const bindingSeparator = ':';
export const modifierDelimiter = '&';

export def parseBinding []: string -> record<key: string, modifiers: list<string>> {
    let split = $in
    | split column -n 2 $bindingSeparator key modifiers
    | first;
    let key = $split.key;
    let modifiers = $split.modifiers?
    | if ($in | is-not-empty) {
        split row $modifierDelimiter
    } else {
        []
    }
    { key: $key, modifiers: $modifiers }
}

export def expressBinding []: record<key: string, modifiers: list<string>> -> string {
    let binding = $in;
    $binding.key
    | append (
        $binding.modifiers | if ($in | is-not-empty) {
            $"($bindingSeparator)($in | str join $modifierDelimiter)"
        } else { '' }
    )
    | str join
}

export def applyShift []: record<key: string, modifiers: list<string>> -> record<key: string, modifiers: list<string>> {
    let capture = $in;
    if ('shift' not-in $capture.modifiers) {
        return capture;
    }
}