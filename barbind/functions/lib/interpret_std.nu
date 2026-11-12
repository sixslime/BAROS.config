
export def parseCapture [
    modifierSeparator = ':',
    modifierDelimiter = '&',
]: string -> record<key: string, modifiers: list<string>> {
    let split = $in
    | split column -n 2 ':' key modifiers
    | first;
    let key = $split.key;
    let modifiers = $split.modifiers?
    | if ($in | is-not-empty) {
        split row '&'
    } else {
        []
    }
    { key: $key, modifiers: $modifiers }
}

export def applyShift []: record<key: string, modifiers: list<string>> -> record<key: string, modifiers: list<string>> {
    let capture = $in;
    if ('shift' not-in $capture.modifiers) {
        return capture;
    }
    
}