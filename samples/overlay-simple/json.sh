#!/usr/bin/env bash
# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Immediately exit if any command fails.
set -e

# --- begin runfiles.bash initialization ---
# Source the runfiles library:
# https://github.com/bazelbuild/bazel/blob/master/tools/bash/runfiles/runfiles.bash
# The runfiles library defines rlocation, which is a platform independent function
# used to lookup the runfiles locations. This code snippet is needed at the top
# of scripts that use rlocation to lookup the location of runfiles.bash and source it
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
    if [[ -f "$0.runfiles_manifest" ]]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
    elif [[ -f "$0.runfiles/MANIFEST" ]]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
    elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
      export RUNFILES_DIR="$0.runfiles"
    fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---

# Launcher for NodeJS applications.
# Find our runfiles. We need this to launch node with the correct
# entry point.
#
# Call this program X. X was generated by a genrule and may be invoked
# in many ways:
#   1a) directly by a user, with $0 in the output tree
#   1b) via 'bazel run' (similar to case 1a)
#   2) directly by a user, with $0 in X's runfiles
#   3) by another program Y which has a data dependency on X, with $0 in Y's
#      runfiles
#   4a) via 'bazel test'
#   4b) case 3 in the context of a test
#   5a) by a genrule cmd, with $0 in the output tree
#   6a) case 3 in the context of a genrule
#
# For case 1, $0 will be a regular file, and the runfiles will be
# at $0.runfiles.
# For case 2 or 3, $0 will be a symlink to the file seen in case 1.
# For case 4, $TEST_SRCDIR should already be set to the runfiles by
# blaze.
# Case 5a is handled like case 1.
# Case 6a is handled like case 3.

case "$0" in
 /*) self="$0" ;;
 *) self="$PWD/$0" ;;
esac

if [[ -n "$RUNFILES_MANIFEST_ONLY" ]]; then
  # Windows only has a manifest file instead of symlinks.
  RUNFILES=${RUNFILES_MANIFEST_FILE%/MANIFEST}
elif [[ -n "$TEST_SRCDIR" ]]; then
  # Case 4, bazel has identified runfiles for us.
  RUNFILES="${TEST_SRCDIR}"
else
  while true; do
    if [[ -e "$self.runfiles" ]]; then
      RUNFILES="$self.runfiles"
      break
    fi

    if [[ $self == *.runfiles/* ]]; then
      RUNFILES="${self%%.runfiles/*}.runfiles"
      # don't break; this is a last resort for case 6b
    fi

    if [[ ! -L "$self" ]]; then
      break;
    fi

    readlink="$(readlink "$self")"
    if [[ "$readlink" = /* ]]; then
      self="$readlink"
    else
      # resolve relative symlink
      self="${self%%/*}/$readlink"
    fi
  done

  if [[ -z "$RUNFILES" ]]; then
    echo " >>>> FAIL: RUNFILES environment variable is not set. <<<<" >&2
    exit 1
  fi
fi
export RUNFILES
export BAZEL_TARGET=//samples/overlay-simple:json
export COMPILATION_MODE="fastbuild"


# Note: for debugging it is useful to see what files are actually present
# This redirects to stderr so it doesn't interfere with Bazel's worker protocol
# find . -name thingImLookingFor 1>&2

readonly vendored_node=""

if [ -n "${vendored_node}" ]; then
  # Use the vendored node path
  readonly node=$(rlocation "${vendored_node}")

  if [ ! -f "${node}" ]; then
      printf "\n>>>> FAIL: The vendored node binary '${vendored_node}' not found in runfiles. <<<<\n\n" >&2
      exit 1
  fi
else
  # Check environment for which node path to use
  unameOut="$(uname -s)"
  case "${unameOut}" in
      Linux*)     machine=linux ;;
      Darwin*)    machine=darwin ;;
      CYGWIN*)    machine=windows ;;
      MINGW*)     machine=windows ;;
      MSYS_NT*)   machine=windows ;;
      *)          machine=linux
                  printf "\nUnrecongized uname '${unameOut}'; defaulting to use node for linux.\n" >&2
                  printf "Please file an issue to https://github.com/bazelbuild/rules_nodejs/issues if \n" >&2
                  printf "you would like to add your platform to the supported rules_nodejs node platforms.\n\n" >&2
                  ;;
  esac

  case "${machine}" in
    # The following paths must match up with _download_node in node_repositories
    darwin) readonly node_toolchain="nodejs_darwin_amd64/bin/nodejs/bin/node" ;;
    windows) readonly node_toolchain="nodejs_windows_amd64/bin/nodejs/node.exe" ;;
    *) readonly node_toolchain="nodejs_linux_amd64/bin/nodejs/bin/node" ;;
  esac

  readonly node=$(rlocation "${node_toolchain}")

  if [ ! -f "${node}" ]; then
      printf "\n>>>> FAIL: The node binary '${node_toolchain}' not found in runfiles.\n" >&2
      printf "This node toolchain was chosen based on your uname '${unameOut}'.\n" >&2
      printf "Please file an issue to https://github.com/bazelbuild/rules_nodejs/issues if \n" >&2
      printf "you would like to add your platform to the supported rules_nodejs node platforms. <<<<\n\n" >&2
      exit 1
  fi
fi

readonly repository_args=$(rlocation "nodejs_linux_amd64/bin/node_repo_args.sh")
MAIN=$(rlocation "googlemaps_js_samples/samples/overlay-simple/json_loader.js")
readonly link_modules_script=$(rlocation "build_bazel_rules_nodejs/internal/linker/index.js")
bazel_require_script=$(rlocation "build_bazel_rules_nodejs/internal/node/bazel_require_script.js")

# Node's --require option assumes that a non-absolute path not starting with `.` is
# a module, so that you can do --require=source-map-support/register
# So if the require script is not absolute, we must make it so
case "${bazel_require_script}" in
  # Absolute path on unix
  /*          ) ;;
  # Absolute path on Windows, e.g. C:/path/to/thing
  [a-zA-Z]:/* ) ;;
  # Otherwise it needs to be made relative
  *           ) bazel_require_script="./${bazel_require_script}" ;;
esac

source $repository_args

ARGS=()
NODE_OPTIONS=()
ALL_ARGS=( $NODE_REPOSITORY_ARGS "$@")
for ARG in "${ALL_ARGS[@]}"; do
  case "$ARG" in
    --bazel_node_modules_manifest=*) MODULES_MANIFEST="${ARG#--bazel_node_modules_manifest=}" ;;
    --nobazel_patch_module_resolver)
      MAIN="node_modules/json/lib/json.js"
      NODE_OPTIONS+=( "--require" "$bazel_require_script" )
      ;;
    --node_options=*) NODE_OPTIONS+=( "${ARG#--node_options=}" ) ;;
    *) ARGS+=( "$ARG" )
  esac
done

# Link the first-party modules into node_modules directory before running the actual program
if [[ -n "$MODULES_MANIFEST" ]]; then
  "${node}" "${link_modules_script}" "${MODULES_MANIFEST}"
fi

# Tell the bazel_require_script that programs should not escape the execroot
# Bazel always sets the PWD to execroot/my_wksp so we go up one directory.
export BAZEL_PATCH_ROOT=$(dirname $PWD)

# The EXPECTED_EXIT_CODE lets us write bazel tests which assert that
# a binary fails to run. Otherwise any failure would make such a test
# fail before we could assert that we expected that failure.
readonly EXPECTED_EXIT_CODE="0"
if [ "${EXPECTED_EXIT_CODE}" -eq "0" ]; then
  # Replace the current process (bash) with a node process.
  # This means that stdin, stdout, signals, etc will be transparently
  # handled by the node process.
  # If we had merely forked a child process here, we'd be responsible
  # for forwarding those OS interactions.
  exec "${node}" "${NODE_OPTIONS[@]}" "${MAIN}" "${ARGS[@]}"
  # exec terminates execution of this shell script, nothing later will run.
fi

set +e
"${node}" "${NODE_OPTIONS[@]}" "${MAIN}" "${ARGS[@]}"
RESULT="$?"
set -e

if [ ${RESULT} != ${EXPECTED_EXIT_CODE} ]; then
  echo "Expected exit code to be ${EXPECTED_EXIT_CODE}, but got ${RESULT}" >&2
  if [ "${RESULT}" -eq "0" ]; then
    # This exit code is handled specially by Bazel:
    # https://github.com/bazelbuild/bazel/blob/486206012a664ecb20bdb196a681efc9a9825049/src/main/java/com/google/devtools/build/lib/util/ExitCode.java#L44
    readonly BAZEL_EXIT_TESTS_FAILED=3;
    exit ${BAZEL_EXIT_TESTS_FAILED}
  fi
else
  exit 0
fi

exit ${RESULT}