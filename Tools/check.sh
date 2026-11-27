#!/bin/zsh
# One command to check everything: the core tests and the Mac build.
#
# Prints one line per step, and on an error only the error lines - the full
# logs are in .build/check/. That way every build costs a few lines
# to read, not a few hundred.
#
#   Tools/check.sh            core and Mac
#
# Touches no iPod.

set -u
cd "${0:A:h}/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
LOGS=.build/check
mkdir -p $LOGS
PROJECT=App/Clickwill.xcodeproj
failed=0

# step NAME command... - one result line, on an error the error lines from the log.
step() {
    local name=$1; shift
    local log=$LOGS/$name.log start=$SECONDS
    if "$@" > $log 2>&1; then
        print -r -- "OK    $name ($((SECONDS - start)) s)${SUMMARY:+ - $SUMMARY}"
    else
        print -r -- "FAIL  $name ($((SECONDS - start)) s) - $log"
        grep -E "error:|: error|✘|failed|FAILED|XCTAssert|Skipped" $log | grep -v "^[[:space:]]*$" \
            | sed -E 's/\x1b\[[0-9;]*m//g' | sort -u | head -25 | sed 's/^/      /'
        failed=1
    fi
    SUMMARY=""
}

# The Xcode project is generated - we refresh it when project.yml or the files changed.
if [[ ! -d $PROJECT || App/project.yml -nt $PROJECT/project.pbxproj ]] \
   || [[ -n "$(find App/Clickwill -newer $PROJECT/project.pbxproj -name '*.swift' -print -quit)" ]]; then
    SUMMARY="" step xcodegen zsh -c "cd App && xcodegen generate"
fi

# The themes module is a plug that can be cut off: only the app's module list and the
# module's own tests name it, and in Package.swift only its test target depends on it.
theme_isolation() {
    local bad
    bad=$(grep -rlE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+ClickwillThemes' Sources App Tests --include='*.swift' \
        | grep -vE '^(App/Clickwill/Shell/Modules\.swift|Tests/ClickwillThemesTests/)')
    [[ -z $bad ]] || { print -r -- "error: ClickwillThemes imported outside Modules.swift: ${bad//$'\n'/ }"; return 1 }
    bad=$(grep -nE 'dependencies:.*"ClickwillThemes"' Package.swift | grep -v 'testTarget(name: "ClickwillThemesTests"')
    [[ -z $bad ]] || { print -r -- "error: a target depends on ClickwillThemes: $bad"; return 1 }
    # In App/project.yml the product is a dependency of the app target only.
    [[ $(grep -c 'product: ClickwillThemes' App/project.yml) -le 1 ]] \
        || { print -r -- "error: ClickwillThemes is a dependency of more than one target in App/project.yml"; return 1 }
}
SUMMARY="" step theme-isolation theme_isolation

SUMMARY=""
step core-tests swift test
[[ -f $LOGS/core-tests.log ]] && SUMMARY_LINES=$(grep -E "Test run with" $LOGS/core-tests.log | sed -E 's/.*Test run with ([0-9]+) tests.*(passed|failed).*/\1 \2/' | paste -sd, -)
[[ $failed == 0 ]] && print -r -- "      tests: ${SUMMARY_LINES:-?}"

step mac-build xcodebuild -project $PROJECT -scheme Clickwill -configuration Debug \
    -derivedDataPath .build/xcode build

exit $failed
