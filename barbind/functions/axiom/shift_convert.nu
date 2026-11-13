#!/env nu

const selfDir = (path self | path expand | path dirname);

use ($selfDir | path join '../lib/axiom.nu') [
    parseBinding,
    expressBinding,
]

def main [
    capture: string,
    oldCaptureStart: string,
    oldCaptureEnd: string,
    newCaptureStart: string,
    newCaptureEnd: string,
] {
    let binding = $capture | parseBinding;
    $binding.modifiers | if ('shift' not-in $in) or ('control' in $in) {
        return $capture;
    };
    let key = $binding.key
    | parse $"($oldCaptureStart){value}($oldCaptureEnd)"
    | first
    | get value -o
    | if ($in | is-not-empty) {
        $"($newCaptureStart)($in)($newCaptureEnd)"
    } else {
        $binding.key
    };
    let modifiers = $binding.modifiers | difference ['shift'];
    {
        key: $key,
        modifiers: $modifiers,
    }
    | expressBinding
}