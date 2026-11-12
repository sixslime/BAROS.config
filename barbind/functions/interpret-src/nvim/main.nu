#!/env nu

def main [capture: string] {
    print -n ($capture | transform);
}

def transform []: string -> string {
    let split = $in
    | split column -n 2 ':' key modifiers
    | first;
    let key = $split.key;
    if ($split.modifiers? | is-empty) {
        return $key;
    };
    let modifiers = $split.modifiers | split row '&';
    
}