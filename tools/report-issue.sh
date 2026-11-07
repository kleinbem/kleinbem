#!/usr/bin/env bash
# Posts an audit report to the open issue titled <title>, only when it differs
# from the last post. With no open issue, a report with findings opens one; a
# clean one doesn't.
#
# Usage: report-issue.sh <title> <report.md> <findings: 0|1>   (needs GH_TOKEN)
set -euo pipefail

title="$1"
report="$2"
findings="$3"

issue="$(gh issue list --state open --search "in:title \"$title\"" --limit 100 --json number,title \
    --jq "map(select(.title == \"$title\"))[0].number // empty")"
if [[ -z "$issue" ]]; then
    if [[ "$findings" == 1 ]]; then
        gh issue create --title "$title" --body-file "$report"
    fi
    exit 0
fi
last="$(gh issue view "$issue" --json body,comments --jq '(.comments | last | .body) // .body')"
if [[ "$last" != "$(cat "$report")" ]]; then
    gh issue comment "$issue" --body-file "$report"
fi
