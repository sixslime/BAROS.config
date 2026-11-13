#!/env nu

def main [capture: string, escapeSequence: string, ...escaped: string] {
    let o = if ($capture in $escaped) {
        $"($escapeSequence)($capture)"
    } else {
        $capture
    };
    print -n $o;
}