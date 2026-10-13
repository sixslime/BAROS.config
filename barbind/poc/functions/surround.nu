#!/env nu

def main [left: string, right: string]: string -> string {
    # $in is the captured text.
    print -n $"($left)($in)$($right)";
}