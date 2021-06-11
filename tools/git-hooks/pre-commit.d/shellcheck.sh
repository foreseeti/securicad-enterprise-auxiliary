#!/bin/sh

set -eux

cd "$(dirname "$0")/../../.."

echo_changed_scripts() {
  set +e
  git diff --cached --name-only --diff-filter=ACMR | grep -e "\.sh$" -e "\.bash$"
  set -e
}

check_scripts() {
  echo "Checking $(echo "$changed_scripts" | wc -l) shell scripts"
  echo "$changed_scripts" | tr "\n" " " | xargs shellcheck
  echo "$changed_scripts" | tr "\n" "\0" | xargs -0 git add -f
}

main() {
  changed_scripts="$(echo_changed_scripts)"
  if [ -z "$changed_scripts" ]; then
    exit
  fi
  check_scripts
}

main
