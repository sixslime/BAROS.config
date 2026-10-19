
export def w [--push (-p), ...message: string]: nothing -> oneof<record<branch: string, hash: string, message: string, diff: list<string>, summary: string>, nothing> {
    ^git add -A;
    let branch = ^git branch --no-color --show-current;
    let diff = getDiff '--staged' 'HEAD';
    if ($diff | is-empty) {
        print -e $"(ansi yellow)No changes to commit. \(($branch))(ansi reset)";
        return null;
    };
    let message = if not ($message | is-empty) {
        $message | str join ' '
    } else {
        '-'
    };
    print -e $"(ansi green)Committing to ($branch)...(ansi reset)";
    ^git commit -qam $message;
    let hash = ^git rev-parse HEAD;
    {
        summary: $diff.summary,
        diff: $diff.changes,
        branch: $branch,
        hash: $hash,
        message: $message,
    }
    | if $push {
        insert push (doPush)
    } else { $in }
}

def getDiff [from: string, to: string]: nothing -> oneof<nothing, record<changes: list<string>, summary: string>> {
    let diffOut = ^git diff $from $to --stat --no-color | lines;
    if ($diffOut | is-empty) { null } else {
        {
            changes: ($diffOut | slice ..(-2)),
            summary: ($diffOut | last),
        }
    }
}

def doPush []: nothing -> oneof<record, record<remote: string, diff: list<string>, summary: string>> {
    let branch = ^git branch --no-color --show-current;
    let upstream = ^git rev-parse --abbrev-ref --symbolic-full-name @{u};
    let diffCode = ^git diff $branch $upstream --quiet | complete | get exit_code;
    if $diffCode == 0 {
        print -e $"(ansi yellow)No differences to push. \(($branch) == ($upstream))(ansi reset)";
        return null;
    };
    let diff = getDiff $branch $upstream;
    print -e $"(ansi green)Pushing ($branch) to ($upstream)...(ansi reset)";
    let completion = ^git push | complete;
    if ($completion.exit_code == 0) {
        {
            summary: $diff.summary,
            diff: $diff.changes,
            remote: $upstream,
        }
    } else {
        print -e $"(ansi light_red)Push failed!(ansi reset)";
        $completion
    }
}
export def wp [...message: string] {
    w -p ...$message | default {
        doPush;
    }
}
