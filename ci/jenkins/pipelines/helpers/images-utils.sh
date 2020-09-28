#!/bin/bash

set -e

: "${BASE_PRJ:=Devel:CaaSP:4.5}"
: "${SRC_PRJ:=${BASE_PRJ}:Containers:CR}"
: "${BRANCH_PRJ:=${BASE_PRJ}:Branches}"
: "${TARGET_BRANCH:=origin/master}"
: "${ARCH:=x86_64}"
: "${REPO:=containers}"
: "${API:=https://api.suse.de}"
: "${G_API:=https://api.github.com}"
: "${G_REPO:=caasp-container-images}"
: "${G_ORG:=davidcassany}"
: "${BUILD_URL:=https://ci.suse.de}"
: "${IMG_NAME_PATTERN:=caasp-.*-image}"

function _gitRoot {
    cd "$(git rev-parse --show-toplevel)"
}

function _abort {
    echo $@ && exit 1
}

function _cmdCheck {
    local cmd=$1
    which ${cmd} > /dev/null || _abort "${cmd} command not in PATH"
}

function _setOSCAuth {
    IBS_CONFIG="$(pwd)/oscrc"
    [[ -z ${IBS_USR+x} ]] && _abort "No IBS user provided"
    [[ -z ${IBS_PSW+x} ]] && _abort "No IBS password provided"

    cat << EOF > "${IBS_CONFIG}"
[general]
apiurl = ${API}

[${API}]
user = ${IBS_USR}
pass = ${IBS_PSW}
EOF
}

function checkVersionChange {
    local images=${1}
    local branch=${2:-${TARGET_BRANCH}}

    for img in ${images}; do
        git diff "${branch}" -- "${img}" | grep -q "^+.*</version>" || \
            _abort "Error: '${img}' does not include any image version change!"
    done
}

function oscCmd {
    [[ -f ${IBS_CONFIG} ]] || _abort "No IBS config file provided"
    osc --config="${IBS_CONFIG}" "$@"
}

function submitMergedPRs {
    local prefix=$1
    local pr

    msg="Automated submission from Jenkins CI"
    for prj in $(oscCmd ls / | grep "${prefix}"); do
        pr=${prj##${prefix}}
        if checkPRisMerged "${pr}"; then
            oscCmd co "${prefix}${pr}"
            pushd "${prefix}${pr}" > /dev/null
                for img in $(ls | grep "${IMG_NAME_PATTERN}"); do
                    pushd "${img}" > /dev/null
                        checkLastCommit
                        req=$(oscCmd sr --yes -m "${msg}" --cleanup | \
                            grep -Eo [[:digit:]]{6})
                        oscCmd request accept -m "${msg}" "${req}"
                    popd > /dev/null
                done
            popd > /dev/null
        fi
    done
}

function checkLastCommit {
    local usr

    usr=$(oscCmd log --csv | head -n1 | cut -d"|" -f2)
    echo "Last commit user is: ${usr}"
    [[ "${usr}" == "${IBS_USR}" ]] || _abort "Last commit is not by OBS bot"
}

function checkPRisMerged {
    local pr=$1
    local org=${2:-${G_ORG}}
    local repo=${3:-${G_REPO}}
    local api=${4:-${G_API}}

    curl -sf "${api}/repos/${org}/${repo}/pulls/${pr}/merge"
}

function listUpdatedImages {
    local branch=${1:-${TARGET_BRANCH}}
    local images

    images=$(git diff --name-only "${branch}" | grep ^caasp.*image | cut -d"/" -f1 | uniq)
    echo "${images}"
}

function branchImages {
    local branchName=$1
    local images=$2
    local srcPrj=${3:-${SRC_PRJ}}
    local branchPrj=${4:-${BRANCH_PRJ}}
    local flags=""

    for img in ${images}; do
        flags="-f --add-repositories"
        oscCmd ls "${srcPrj}" "${img}" >/dev/null || flags+=" -N"
        oscCmd branch "${flags}" "${srcPrj}" "${img}" "${branchPrj}:${branchName}"
        updateImageFromSource "${branchPrj}:${branchName}" "${img}"
    done
}

function updateImageFromSource {
    local image=$2
    local prj=$1
    local obs_files="ci/packaging/suse/obs_files"
    local tmpDir=$(mktemp -d -t image_XXXX --tmpdir=.)

    rm -f "${obs_files}"/*

    pushd "${image}" > /dev/null
        make suse-package
    popd > /dev/null
    oscCmd co -o "$tmpDir" "${prj}/${image}"
    find "${tmpDir}" -maxdepth 1 -type f ! -name '*.changes' -delete
    cp -v "${obs_files}"/* "${tmpDir}"
    pushd "${tmpDir}" > /dev/null
        cat "${image}.changes" >> "${image}.changes.append"
        mv "${image}.changes.append" "${image}.changes"
        oscCmd addremove
        oscCmd ci "${tmpDir}" -m "Automated commit by ${IBS_USR} on the CI"
    popd > /dev/null
}

function waitForImagesBuild {
    local prj=$1
    local images=$2
    local arch=${3:-${ARCH}}
    local repo=${4:-${REPO}}

    # TODO ensure the build started
    #lastBuidRev=$(oscCmd buildhistory -l 1 --csv "${prj}" "${image}" \
    #    "${repo}" "${arch}" | cut -d"|" -f 3)
    #lastCmtRev=$(oscCmd log --csv "${prj}" "${image}" | head -n1 | cut -d"|" -f1)

    for img in ${images}; do
        if ! oscCmd results -a "${arch}" -r "${repo}" -w "${prj}" "${img}" | \
            grep -q "succeeded"; then
            _abort "${img}" build failed
        fi
    done
}

function sentStatuses {
    local status=$1
    local desc=$2
    local context=${3:-continuous-integration/jenkins}
    local org=${4:-${G_ORG}}
    local repo=${5:-${G_REPO}}
    local token=${6:-${GITHUB_TOKEN}}
    local url=${7:-${BUILD_URL}}

    commit=$(git rev-parse HEAD)
    status_json="{\"state\": \"${status}\", \"target_url\": \"${url}\", \"description\": \"${desc}\", \"context\": \"${context}\"}"
    curl -sS "${G_API}/repos/${org}/${repo}/statuses/${commit}?access_token=${GITHUB_ACCESS}" \
        -H  "Content-Type: application/json" -X POST -d "${status_json}" > /dev/null
}

_gitRoot || _abort "Not inside the git repository"

_cmdCheck osc
_cmdCheck curl

_setOSCAuth

function=$1
shift

type $function >/dev/null 2>&1 || _abort "method '${function}' not found"
$function "$@"

