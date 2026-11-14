#!/env nu

def main [capture: string, escapeSequence: string, escaped: string] {
    let o = $capture
    | str replace -a $escaped $"($escapeSequence)($escaped)";
    print -n $o;
}