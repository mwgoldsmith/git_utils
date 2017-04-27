#!/bin/bash

declare -r _SCRIPT=${0##*/}
declare -r _SCRIPT_NAME=${_SCRIPT%.*}
declare -r _SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

declare -i _HAS_TPUT="$( which tput >/dev/null 2>&1 && 1 || 0 )"
declare -i _NUM_COLS=0
declare -i _VERBOSITY=0

declare -r _HOSTURL="github.com"
declare _SSH _HOSTUSER
declare _OS _GIT _GIT_USER _GIT_VERSION

#######
# gitils_init_colours()
#
# Initializes global variables used for foreground colour values along with
# _HAS_TPUT and _NUM_COLS.
#######
gitils_init_colours() {
  if ! $_HAS_TPUT; then
    _NUM_COLS=0
    return
  fi

  local num=$( tput colors )
  if test -n "$num" && test "$num" -ge 8; then
    _BOLD=$( tput bold )
    _UNDERLINE=$( tput smul )
    _WHITE=$( tput setaf 7 )
    _AQUA=$( tput setaf 6 )
    _PURPLE=$( tput setaf 5 )
    _BLUE=$( tput setaf 4 )
    _ORANGE=$( tput setaf 3 )
    _GREEN=$( tput setaf 2 )
    _RED=$( tput setaf 1 )
    _BLACK=$( tput setaf 0 )
    _NORMAL=$( tput sgr0 )
  fi

  _NUM_COLS=$( tput cols )
}

#######
# gitils_display_msg_line(action[, colour], message[, handle])
#
# $1 action    The name of the action which a status message is being displayed for
# $2 colour    The foreground colour to use to display the message.
# $3 message   The status message to display
# $4 handle    The file handle to redirect output to. Defaults to 1 (stdout) if not
#              specified. This argument is optional, however if provided then the
#              'colour' optional argument must also be provided.
#######
gitils_display_msg_line() {
  local action="$1 "
  local colour status handle

  if [ $# -gt 2 ]; then
    colour=${!"_$2"}
    shift
  else
    colour=""
  fi

  status="$2"
  handle=${3:-1}
  if $_HAS_TPUT; then
    local pad=$( eval "printf '%0.1s' '.'{1..$_NUM_COLS}" )
    local padlen=$((_NUM_COLS-${#action}-${#status}-3))

    printf '%s%*.*s [%s]\n' "$_BOLD${action}$_NORMAL" 0 "$padlen" "$pad" "$colour${status}$_NORMAL" >&$handle
  else
    printf '%s - %s\n' "$action" "$status" >&$handle
  fi
}

#######
# gitils_display_status_line(action, message)
#
# $1 action    The name of the action which a message is being displayed for
# $2 message   The message to display. It will be written to stderr.
#######
gitils_display_status_line() {
  local action="$1"
  local message="$2"

  gitils_display_msg_line "$action" GREEN "$message"
}

#######
# gitils_display_debug_line([verbosity,] message)
#
# $1 verbosity Optional verbosity level. If provided, the message will only be
#              displayed if the value less than or equal to the current verbosity
#              level.
# $2 message   The message to display.
#######
gitils_display_debug_line() {
  local message stamp

  if [ $# -gt 1 ]; then
    [ ${_VERBOSITY-0} -lt $1 ] && return
    shift
  fi

  message="$1"
  stamp=$(date +"%F %T.%3N")
  gitils_display_msg_line "DEBUG - $stamp" "$message"
}

#######
# gitils_display_error_line([code,] action, message)
#
# $1 code      Optional exit code. If provided, the script will terminate using
#              this argument as the exit code value.
# $2 action    The name of the action which a message is being displayed for
# $3 message   The message to display. It will be written to stderr.
#######
gitils_display_error_line() {
  local code action message

  if [ $# -gt 2 ]; then
    code=$1
    shift
  fi

  action="$1"
  message="$2"
  gitils_display_msg_line "ERROR - $action" RED "$message" 2

  test -n "$code" && exit $code
}

#######
# gitils_display_array(array)
#
# $1 array     The name of the array variable to dump the elements of.
#######
gitils_display_array() {
  local name="$1" a="${!1}"
  local i=0

  printf '  %s=\n' "$name"
  for e in $a; do
    printf '    [%d] = "%s"\n' $i "$e"
    i=$(( i + 1 ))
  done
}

#######
# gitils_die([code][, message])
#
# Displayed an optional message to stderr if provided; terminates the script with
# the optional exit code.
#
# $1 code      Optional argument. If provided, it will be used as the exit
#              code and the script will terminate. Otherwise, it will return.
# $2 message   Optional argument. If provided, it will display the message
#              before exiting.
#######
gitils_die() {
  if [[ "$1" =~ "^[0-9]*" ]] && [ "${#1}" -le 3 ]; then
    local -r code=$1
    shift
  fi

  [ -n "$*" ] && printf "%s\n" "$*" >&2

  exit "${code-0}"
}

#######
# gitils_display_usage(code)
#
# $1 code      Optional argument. If provided, it will be used as the exit
#              code and the script will terminate. Otherwise, it will return.
#######
gitils_display_usage() {
  local -r usage=$(cat << EOF
  Usage: $(basename $0) [todo]

  Options:
    -v, --verbose          Enable verbose output.

  Actions:
        --help             Display usage and various options.

EOF
)
  echo "$usage"

  test $# -gt 0 && exit $1
}

#######
# gitils_init_os()
#
# return       If the OS could be determined and is supported, 1; otherwise 0.
#######
gitils_init_os() {
  case "$(uname -s)" in
  Darwin)
    _OS="_mac"
    ;;
  Linux)
    _OS="_linux"
  CYGWIN*|MINGW32*|MSYS*)
    _OS="_windows"
    ;;
  *)
    return 0
    ;;
  esac

  return 1
}

#######
# gitils_init_test_ssh()
#
# return       If the git can access repositories via SSH, 1; otherwise 0.
#######
gitils_init_test_ssh() {
  # Check if an SSH key exists for github.com
  if [ -f ~/.ssh/config ]; then
    local line fname user found=0

    while read -r line; do
      if [ $found ]; then
        test -z "$user" && user=${line/  User /}
        test -z "$fname" && fname=${line/  IdentityFile /}
        test $(( $user ^ $fname)) && break || continue
      fi

      found=$( test "$line" != "  HostName $_HOSTURL"; echo $? )
    done < <( cat ~/.ssh/config )

    if [ $found ]; then
      _HOSTUSER="$user"
    else
      echo "No SSH key file exists for host '$_HOSTURL'"
    fi
  fi

  _SSH=0

  if [ -n "$_HOSTUSER" ]; then
    local result=$( ssh -T ${_HOSTUSER}@${_HOSTURL} )
    [[ "$result" =~ "^.*You've successfully authenticated.*" ]] && _SSH=1
  fi

  return $_SSH
}

#######
# gitils_init()
#
#core.repositoryformatversion=0
#core.filemode=true
#core.bare=false
#core.logallrefupdates=true
#core.ignorecase=true
#core.precomposeunicode=true
#######
gitils_init() {
  gitils_init_colours

  if gitils_init_os; then
    echo "Current executing environment is not supported"
    return 1
  fi

  # Determine if git exists, and if so, the version and various configuration values
  _GIT=$( which git )
  test -z "$_GIT" && return 2

  _GIT_VERSION=$( $_GIT --version | sed -e 's/^[^0-9]*\([0-9]*.*\)$/\1/' )
  _GIT_USER=$( $_GIT config --get user.name 2>/dev/null )

  gitils_init_test_ssh
}

gitInitCredentialHelper() {
  case $_OS in
  $OS_MAC)
    git config --global credential.helper osxkeychain
    ;;

  $OS_LNX)
    git config --global credential.helper cache
    git config --global credential.helper 'cache --timeout=900'
    ;;

  $OS_WIN)
    git config --global credential.helper wincred
    ;;

  *)
    exit 127
    ;;
  esac
}

gitils_init

exit




_ROOT_PATH="$( readlink -m "${_SCRIPT_PATH}/.." )"
_PROJECTS_PATH="$( readlink -m "${_SCRIPT_PATH}/../.." )"
_BUILD_PATH="$( readlink -m "${_PROJECTS_PATH}/build" )"
declare -i _LIST=0
declare -i _SYNC=0
declare -i _UPDATE=0
declare -i _BUILD=0
declare -a _DEPS=( )

#######
# displayDependencies()
#
# Displays the dependency array as a top-down tree structure.
#######
displayDependencies() {
  local name=
  local version=
  local depth=
  local line=
  local prev_depth=${#_DEPS[@]}
  local line_char=" "

  line=$( basename "${_ROOT_PATH}" )
  for dep in "${_DEPS[@]}"; do
    depth=$( echo "$dep" | cut -d'|' -f6 )
    if [ "${prev_depth}" -gt "${depth}" ]; then
      if [ "${prev_depth}" -eq "${#_DEPS[@]}" ]; then
        line_char=" "
      else
        line_char="└"
      fi
    else
      line_char="├"
    fi

    prev_depth="${depth}"

    echo "${line}${line_char} ${name} ${version}"

    line="  "
    name=$( echo "$dep" | cut -d'|' -f1 )
    version=$( echo "$dep" | cut -d'|' -f3 )
    while [ $depth -gt 0 ]; do
      line="${line}|  "
      depth=$(($depth-1))
    done

    version="(${version})"
  done

  echo "${line}└ ${name} ${version}"
}

#######
# displayCurrentState()
#######
displayCurrentState() {
  cat << EOF

Current state:
  _VERBOSITY=${_VERBOSITY}
  _SCRIPT=${_SCRIPT}
  _SCRIPT_NAME=${_SCRIPT_NAME}
  _SCRIPT_PATH=${_SCRIPT_PATH}
  _ROOT_PATH=${_ROOT_PATH}
  _PROJECTS_PATH=${_PROJECTS_PATH}
  _BUILD_PATH=${_BUILD_PATH}
  _LIST=${_LIST}
  _SYNC=${_SYNC}
  _UPDATE=${_UPDATE}
  _BUILD=${_BUILD}
  _HAS_TPUT=${_HAS_TPUT}
  _NUM_COLS=${_NUM_COLS}
EOF

  gitils_display_array _DEPS
}

#######
# getCurRepoName()
#######
getCurRepoName() {
  local name=$( git remote show -n origin 2>/dev/nul | grep -i fetch | sed  -e 's|.*/\(.*\)\.git.*|\1|' )
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo "${name}"

  return 0
}

#######
# getDependencyItem(name)
#
# Get the entry for the specified dependency which was built from executing parseDependencies()
#
# $1 name      The name of the dependency
#
# return       If successful, the return code is 1. Otherwise, it is 0.
#######
getDependencyItem() {
  local name=$1
  local cur=

  for dep in "${_DEPS[@]}"; do
    cur=$( echo "$dep" | cut -d'|' -f1 )
    if [ "${name}" == "${cur}" ]; then
     echo "$dep"
     return 1
   fi
  done

  return 0
}

#######
# gitStripRepoUrl(url)
#
# Removes protocol, host, user, and port information from the given git repo URL. This
# allows repo URLs to be compared based on the two segments which should be invariable:
# the repo path and name.
#
# $1 url       The git repo URL.
#######
gitStripRepoUrl() {
  local url="$1"

  echo "${url}" | sed -e 's:^\(\(ssh\|https\|http\|file\|rsync\|git\)\:///*\)[^/]*/::' -e 's:git@[^\:]*\:::' -e 's:/$::'
}

#######
# gitCompareRepoUrl(url_a, url_b)
#
# Compares the two specified git repository URLs with each other.
#
# $1 url_a    The git repo URL to compare to.
# $2 url_b    The git repo URL to compare with.
#
# return       If the given URLs are exactly the same, 2. If the URLs are the same
#              based on path and name, 1; otherwise if the URLs are different, 0.
#######
gitCompareRepoUrl() {
  local url_a="$1"
  local url_b="$2"

  [ "${url_a}" == "${url_b}" ] && return 2

  url_a=$( gitStripRepoUrl "${url_a}" )
  url_b=$( gitStripRepoUrl "${url_b}" )

  [ "${url_a}" == "${url_b}" ] && return 1

  return 0
}

#######
# gitEnsureRemoteSet(remote, url)
#
# Checks that the URL of the remote with the given name is set to the given URL. If not,
# the URL of the remote will be changed if possible. The current working directory is
# assumed to be within the local repository of the repo the URL is being compared with.
#
# $1 remote    The name of the remote to verify and change if needed.
# $2 url       The URL which the remote should be set to.
#
# return       If the URL of the given remote is now the URL it is required to be, 0;
#              otherwise, 1.
#######
gitEnsureRemoteSet() {
  local remote="$1"
  local url_a="$2"
  local url_b=$( git remote show | grep "$remote" >/dev/nul && git remote get-url "$remote" 2>/dev/nul )
  local change=

  # Ensure remote is properly set
  if [ -z "${url_b}" ]; then
    gitils_display_debug_line 1 "Remote $remote does not currently exist"
    change=4
  else
    gitCompareRepoUrl "${url_a}" "${url_b}"
    change=$?
  fi

  if [ $change -eq 1 ]; then
    gitils_display_debug_line 1 "Changing remote URL for $remote from '$url_b' to '$url_a'"

    # determine if working directory is dirty or not
    if [ -z $( git status --porcelain -u | sed -e 's/^\([MADRCU ?]\{2\}\).*$/\1/' | sort | uniq -c ) ]; then
      git remote set-url "$remote" "$url_a"
    else
      gitils_display_error_line "Git repository" "Cannot update remote URL; working directory is dirty"
      return 1
    fi
  elif [ $change -eq 4 ]; then
    gitils_display_debug_line 1 "Creating remote $remote with URL $url_a"
    git remote add "$remote" "$url_a"
  elif [ $change -eq 0 ]; then
    gitils_display_error_line "Git repository" "Cannot update remote URL $remote to '$url_a'"
    return 1
  fi

  gitils_display_status_line "Git repository" "Remote URL for $remote set to '$url_a'"
  return 0
}

#######
# gitFetchChanges(remote[, branch])
#
# Fetches changes from the given remote and checks if the optionally specified branch
# contained changes
#
# $1 remote    The name of the remote to verify and change if needed.
# $2 branch    The branch to check if changes were fetched from the remote
#
# return       If the branch is specified and changes between the local and remote were
#              fetched for it, 1; otherwise, 0.
#######
gitFetchChanges() {
  local remote="$1"
  local branch="$2"
  local branch_updated=0
  local diff=

  gitils_display_status_line "Git repository" "Fetch changes for remote '$remote'"

  local output=$( git fetch "${remote}" 2>&1 )
  echo "${output} :::::: $?"
  output=$(echo "${output}" | grep "^ .*$" | sed -e 's/->//' -e 's/  */ /g' )
  if [ -z "$output" ]; then
    gitils_display_debug_line 1 "No changes fetched"
  fi

  if [ -n "$branch" ]; then
    git branch -a | grep "remotes/${remote}/${branch}$$" >/dev/nul
    if [ $? -eq 0 ]; then
      gitils_display_status_line "Git repository" "Branch '${remote}/${branch}' does exist"
    fi
    diff=$( echo "$output" | grep "${remote}/${branch}$" | cut -d' ' -f2 | sed -e 's:^\([a-f0-9]*\.\.[a-f0-9]*\):\1:' )
    echo "dif: ::::; $diff"
    if [ -n "$diff" ]; then
       diff=$(git rev-list --left-right --count ${diff} | sed -e 's:[\t ]: ahead \| :' -e 's:$: behind:' )
       gitils_display_status_line "Git repository" "Changes fetched for branch '${branch}': ${diff}"
       return 1
    fi
  fi

  return 0
}

gitMergeChanges() {
  local remote="$1"
  local branch="${2:-master}"

  git checkout "${branch}"
  result=$( git merge "origin/${branch}" )
  if [ $(echo "$result" | grep -c "Automatic merge failed") != "0" ]; then
    gitils_display_error_line "Git repository" "Merge conflict on remote '${remote}' with branch '${branch}'"
    return 0
  fi
  git push

  return 1
}


#######
# gitInitRepo(name, merge_def, merge_up)
#
# Initializes a local git repository for a dependency by the given name. Changes from
# the default remote (and upstream remote if present) are merged with the local repo if
# it did not already exist. If the repo did exist locally, it will only be merged with
# the remote(s) if the specified param is given. If the local repo exists and has
# unstaged or untracked changes which have not been committed and pushed, a failure will occur,
#
# Note, if a repo exists with the specified name but the remote or upstream URL are
# different than what has been retrieved via dependency parsing, it will be updated.
#
# $1 name      The repository name.
# $2 default   Indicates action to take for the default remote. Can be 'fetch', 'merge',
#              or 'none' by default. If 'fetch', changes from the default remote are
#              fetched. If 'merge', changes from the default remote are fetched and then
#              merged. For all cases (including 'none'), if the default remote points to
#              a different repository than than exists in the dependency tree, the remote
#              will be updated. If the working directory is dirty, attempting  to change
#              the remote will result in an error.
# $3 upstream  Indicates action to take for the upstream remote if one exists in the
#              dependency tree. Can be 'fetch', 'merge', or 'none' by default. If 'fetch',
#              changes from the upstream remote are fetched. If 'merge', changes from the
#              upstream remote are fetched and then merged. For all cases (including 'none'),
#              if the upstream remote points to a different repository than than exists in
#              the dependency tree, the remote will be updated. If the working directory is
#              dirty, attempting  to change the remote will result in an error.
#
# return       If successful, the return code is 0. Otherwise, it may be one of the
#              below error codes:
#                1  Name of repo does not exist in dependency tree.
#                2  Directory for the local repository is not a valid it repo.
#                3  Failed to ensure the URL for a remote is as required.
#######
gitInitRepo() {
  local name="$1"
  local default="${2:-none}"
  local upstream="${3:-none}"
  local dep_path="${_PROJECTS_PATH}/${name}"

  local dep_item=$( getDependencyItem "${name}" )
  if [ -z $dep_item ]; then
    gitils_display_error_line "Git repository" "${name} is not a known dependency"
    return 1
  fi

  local branch=$( echo "$dep_item" | cut -d'|' -f2 )
  local default_url=$( echo "$dep_item" | cut -d'|' -f4 )
  local upstream_url=$( echo "$dep_item" | cut -d'|' -f5 )

  if [ -d "$dep_path" ]; then
    gitils_display_debug_line 1 "Path for repo '$name' exists locally"

    pushd "$dep_path" >/dev/nul

    # check if path is a valid git repository
    git status >/dev/nul 2>&1
    if [ $? -eq 128 ]; then
      gitils_display_error_line "Git repository" "'$name'' is not a valid git repository"
      popd >/dev/nul
      return 2
    fi

    # Make sure this is set before verifying the remotes
    # If a remote exists which needs to be changed, this config value can alter
    # whether a working directory is determined to be dirty or not and thus whether
    # or not it will be successful.
    git config --local core.autocrlf true

    gitils_display_status_line "Git repository" "Verifying and updating remotes"

    # Ensure default remote is properly set
    gitEnsureRemoteSet "origin" "$default_url"
    if [ $? -ne 0 ]; then
      popd >/dev/nul
      return 3
    fi

    # Ensure upstream remote is properly set
    if [ -n "${upstream_url}" ]; then
      gitEnsureRemoteSet "upstream" "${upstream_url}"
      if [ $? -ne 0 ]; then
        popd >/dev/nul
        return 3
      fi
    else
      gitils_display_debug_line 1 "No upstream remote URL for ${name}"
    fi

    if [ "${default}" == "fetch" -o "${default}" == "merge" ]; then
      gitFetchChanges "origin" "${branch}"
      if [ $? -eq 1 ] && [ "${default}" == "merge" ]; then
        gitMergeChanges "origin" "${branch}"
      fi
    fi

    if [ "${upstream}" == "fetch" -o "${upstream}" == "merge" ]; then
      gitFetchChanges "upstream" "${branch}"
      if [ $? -eq 1 ] && [ "${upstream}" == "merge" ]; then
        gitMergeChanges "upstream" "${branch}"
      fi
    fi

    popd >/dev/nul
  else
    gitils_display_debug_line 1 "Path for repo '${name}' does not exist locally"

    # display debug msg: cloning remote repo
    # clone the repo
    # cd into repo path
    # set config for core.autocrlf
    # if dependency tree has an upstream remote
    #   set upstream remote

    if [ "${upstream}" == "fetch" -o "${upstream}" == "merge" ]; then
      gitils_display_debug_line 1 "Fetch changes for remote 'upstream'"
      # display debug msg: sync with upstream remote
      # if dirty flag is set
        # display error
        # return
      # get current HEAD
      # fetch from upstream remote
      # if cannot connect to repo
        # display error
        # return
      # if new HEAD is different than previous
        # display debug msg: retrieved changes from remote
        # if merge with upstream remote is true
          # merge changes
    fi
  fi
}

#######
# parseDependencies([depth][, parent])
#
# $1 depth     The zero-based depth of the dependencies being parsed in the
#              dependency hierarchy. If not provided, it defaults to 0.
# $2 parent    The name of the dependency to parse the dependencies of. If not
#              provided, the name of the root project is assumed.
#######
parseDependencies() {
  local name=
  local depth=${1:-0}
  local parent=${2:-}
  local dep_path=
  local origin=
  local upstream=

  if [ $# -lt 2 ]; then
    if [ ${#_DEPS[@]} -gt 0 ]; then
      gitils_display_status_line "Parse dependencies" "Dependency tree already parsed"
      return
    fi

    dep_path="${_ROOT_PATH}"
    parent=$( basename "${_ROOT_PATH}" )
    gitils_display_status_line "Parse dependencies" "$parent (root project)"
  else
    dep_path="${_PROJECTS_PATH}/${parent}"
    gitils_display_debug_line 1 "Parse dependencies parent $parent"
    if [ ! -d "$dep_path" ]; then
      gitils_display_msg_line "Parse dependencies" RED "$parent (no local repository found)"
      gitInitRepo "${parent}" "none" "none"
    else
      gitils_display_status_line "Parse dependencies" "$parent"
      [ $_SYNC -eq 1 ] && origin="merge" || origin="fetch"
      [ $_UPDATE -eq 1 ]&& upstream="merge" || upstream="fetch"
      gitInitRepo "${parent}" "${origin}" "${upstream}"
    fi
  fi

  if [ ! -f "${dep_path}/projects/deps.sh" ]; then
    gitils_display_debug_line 1 "No dependencies for $parent are present"
    return
  fi

  pushd "${dep_path}/projects" > /dev/nul

  while read -r line; do
    name=$( echo "$line" | cut -d'|' -f1 )

    _DEPS+=( "${line}|${depth}|${parent}" )

    if ! getDependencyItem "$name" > /dev/nul; then
      ((depth++))
      parseDependencies $depth $name
      ((depth--))
    fi
  done < <( ./deps.sh )

  popd > /dev/nul
}

###############################################################################
# Initialize
###############################################################################
initColours

if [[ $# -eq 0 ]]; then
  displayUsageAndDie 1
fi

###############################################################################
# Parse arguments
###############################################################################
while [[ $# > 0 ]]; do
  case "$1" in
    -l|--list)
      _LIST=1
      ;;
    -s|--sync)
      _SYNC=1
      ;;
    -u|--update)
      _UPDATE=1
      ;;
    -b|--build)
      _BUILD=1
      ;;
    --help)
      displayUsageAndDie 0
      ;;
    -v|--verbose)
      _VERBOSITY=$(( _VERBOSITY + 1 ))
      ;;
    *)
      echo "Unknown option provided: $1"
      displayUsageAndDie 1
      ;;
  esac
  shift
done

test ${_VERBOSITY} -gt 1 && displayCurrentState

if [ ! -d "$_BUILD_PATH" ]; then
  gitils_display_debug_line 1 "Creating build path: $_BUILD_PATH"
  mkdir "$_BUILD_PATH"
fi

if [ $_LIST -eq 1 ]; then
  gitils_display_status_line "Action" "List dependencies"
  parseDependencies

  printf "\n"
  displayDependencies

  # sync and update actions are performed while parsing dependencies
  _SYNC=2
  _UPDATE=2
fi

if [ $_SYNC -gt 0 ]; then
  if [ $_SYNC -eq 1 ]; then
    gitils_display_status_line "Action" "Synchronize local dependencies with their remote"
    parseDependencies

    # sync and update actions are performed while parsing dependencies
    _UPDATE=2
  else
    gitils_display_status_line "Action" "Local dependencies already synchronized with their remote"
  fi
fi

if [ $_UPDATE -eq 1 ]; then
  if [ $_UPDATE -eq 1 ]; then
    gitils_display_status_line "Action" "Update dependencies from upstream"
    parseDependencies
  else
    gitils_display_status_line "Action" "Local dependencies already updated from their upstream remotes"
  fi
fi

if [ $_BUILD -eq 1 ]; then
  gitils_display_status_line "Action" "Build dependencies"
  parseDependencies
fi



#######
# gitCloneRepo()
#######
# gitCloneRepo() {
  # local dep_item=$( getDependencyItem "${1}" )
  # local retrieve="${2:-n}"
  # local update="${3:-n}"
  # local name=$( echo "$dep_item" | cut -d'|' -f1 )
  # local branch=$( echo "$dep_item" | cut -d'|' -f2 )
  # local repo_url=$( echo "$dep_item" | cut -d'|' -f4 )
  # local upstream_url=$( echo "$dep_item" | cut -d'|' -f5 )
  # local dep_path="${_PROJECTS_PATH}/${name}"
  # local dir=$( pwd -P )
  # local old_version=
  # local new_version=

  # if [ ! -d "$dep_path" ]; then
    # echo "Downloading (via git clone) ${dep_path} from ${repo_url}"
    # rm -rf "$dep_path.tmp"
    # git clone "$repo_url" "$dep_path.tmp" || return 1

    # mv "$dep_path.tmp" "$dep_path"
    # echo "Done git cloning to $dep_path"
    # cd "$dep_path"
  # else
    # cd "$dep_path"
    # if [[ "$retrieve" = "y" ]]; then
      # git fetch
    # fi
  # fi

  # old_version=`git rev-parse HEAD`

  # if [[ -z "$branch" ]]; then
    # echo "Checking out master"
    # git checkout master || exit 1
    # if [[ "$retrieve" = "y" ]]; then
      # echo "Updating $name to latest version [origin/master]..."
      # git merge origin/master || exit 1
    # fi
  # else
    # echo "Checking out $branch"
    # git checkout "$branch" || exit 1
    # git merge "$branch" || exit 1
  # fi

  # new_version=`git rev-parse HEAD`
  # if [[ "$old_version" != "$new_version" ]]; then
    # echo "Local repo retrieved changes"
  # else
    # echo "Local repo up to date"
  # fi

  # cd "${dir}"
# }

