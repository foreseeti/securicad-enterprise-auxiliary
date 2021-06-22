#!/bin/sh

# Copyright 2020-2021 Foreseeti AB <https://foreseeti.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

cd "$(dirname "$0")/../../.."

echo_changed_scripts() {
  set +e
  git diff --cached --name-only --diff-filter=ACMR | grep -e "\.sh$" -e "\.bash$"
  set -e
}

check_scripts() {
  echo "Checking $(echo "$changed_scripts" | wc -l) shell scripts"
  echo "$changed_scripts" | tr "\n" "\0" | xargs -0 shellcheck
}

main() {
  changed_scripts="$(echo_changed_scripts)"
  if [ -z "$changed_scripts" ]; then
    exit
  fi
  check_scripts
}

main
