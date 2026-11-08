# Return to an up-to-date default branch after a PR was merged, as fast as
# possible. Used by the VS Code task "Git: Return to updated main".
#
# Why it is fast: the usual "switch to main, then pull" updates the working
# tree twice (old main, then new main) - slow after a large PR. Here the local
# default branch is first moved to the fetched commit WITHOUT checking it out,
# then checked out once.
#
# Safe: stops on uncommitted changes; only fast-forwards; deletes the branch
# you left only when git confirms it is merged into main or matches what was
# pushed (git branch -d), otherwise it just tells you.

[CmdletBinding()]
param(
    [string] $Remote = 'origin'
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)." }
}

if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
    throw 'Not inside a git repository.'
}

if (git status --porcelain --untracked-files=no) {
    throw 'There are uncommitted changes. Commit or stash them first.'
}

# Default branch of the remote (main, master, ...); fall back to "main".
$defaultRef = git symbolic-ref --quiet --short "refs/remotes/$Remote/HEAD" 2>$null
$default = if ($defaultRef) { $defaultRef -replace "^$Remote/", '' } else { 'main' }

$current = git branch --show-current

# Fetch only the default branch: the fastest fetch. (Other remote-tracking
# branches are not pruned here; run "git fetch --prune" for that.)
Write-Host "Fetching $Remote/$default..."
Invoke-Git fetch --no-tags $Remote $default

if ($current -eq $default) {
    Invoke-Git merge --ff-only "$Remote/$default"
} else {
    # Move the local default branch to the fetched commit without a checkout.
    # (Creates it if it does not exist locally yet.)
    $localExists = git show-ref --verify --quiet "refs/heads/$default"; $localExists = ($LASTEXITCODE -eq 0)
    if ($localExists) {
        $isAncestor = git merge-base --is-ancestor $default "$Remote/$default"; $isAncestor = ($LASTEXITCODE -eq 0)
        if (-not $isAncestor) {
            throw "Local '$default' has commits that are not on $Remote/$default. Resolve that by hand."
        }
        Invoke-Git update-ref "refs/heads/$default" "$Remote/$default"
    } else {
        Invoke-Git branch --track $default "$Remote/$default"
    }

    Write-Host "Switching to $default..."
    Invoke-Git switch $default

    # Tidy up the branch we came from, only if git agrees it is merged.
    if ($current) {
        git branch -d $current 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Deleted merged branch '$current'."
        } else {
            $upstreamGone = git for-each-ref --format='%(upstream:track)' "refs/heads/$current"
            if ($upstreamGone -eq '[gone]') {
                Write-Host "Branch '$current' was deleted on $Remote (probably squash-merged). Delete it with: git branch -D $current"
            } else {
                Write-Host "Kept branch '$current' (not merged into $default)."
            }
        }
    }
}

Write-Host "Done: $default is at $(git log -1 --format='%h %s')."
