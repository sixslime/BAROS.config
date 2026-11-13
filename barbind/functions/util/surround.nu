#!/env nu

def main [capture: string, left: string, right: string] {
    print -n $"($left)($capture)($right)"
}