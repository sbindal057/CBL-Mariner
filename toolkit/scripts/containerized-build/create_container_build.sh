#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -e

switch_to_red_text() {
    printf "\e[31m"
}

switch_to_normal_text() {
    printf "\e[0m"
}

print_error() {
    echo ""
    switch_to_red_text
    echo ">>>> ERROR: $1"
    switch_to_normal_text
    echo ""
}

help() {
echo "
Usage:
sudo make containerized-rpmbuild [REPO_PATH=/path/to/CBL-Mariner] [MODE=test|build] [VERSION=1.0|2.0] [MOUNTS=/path/in/host:/path/in/container ...] [ENABLE_REPO=y] [BUILD_MOUNT=/path/to/build/chroot/mount]

Starts a docker container with the specified version of mariner.

Optional arguments:
    REPO_PATH:      path to the CBL-Mariner repo root directory. default: "current directory"
    MODE            build or test. default:"build"
                        In 'test' mode it will use a pre-built mariner chroot image.
                        In 'build' mode it will use the latest published container.
    VERISION        1.0 or 2.0. default: "2.0"
    MOUNTS          Mount a host directory into container. Should be of form '/host/dir:/container/dir'. For multiple mounts, please use space (\" \") as delimiter
                        e.g. MOUNTS=\"/host/dir1:/container/dir1 /host/dir2:/container/dir2\"
    BUILD_MOUNT     path to folder to create mountpoints for container's BUILD and BUILDROOT directories.
                        Mountpoints will be ${BUILD_MOUNT}/container-build and ${BUILD_MOUNT}/container-buildroot. default: $REPO_PATH/build
    ENABLE_REPO:    Set to 'y' to use local RPMs to satisfy package dependencies. default: n

    * User can override Mariner make definitions. Some useful overrides could be
                    SPECS_DIR: build specs from another directory like SPECS-EXTENDED by providing SPECS_DIR=path/to/SPECS-EXTENDED. default: $REPO_PATH/SPECS
                    SRPM_PACK_LIST: provide a list of SRPMS to build by providing SRPM_PACK_LIST=\"srpm1 srpm2 ...\". default: builds all SRPMS from $SPECS_DIR
                    RPMS_DIR: choose which built RPMs to mount into container by providing RPMS_DIR=path/to/custom/out/RPMS. default: $REPO_PATH/out/RPMS
                    Refer to toolkit/Makefile for default definitions.
To see help, run 'sudo make containerized-rpmbuild-help'
"
}

build_worker_chroot() {
    pushd $toolkit_root
    echo "Building worker chroot..."
    make chroot-tools REBUILD_TOOLS=y > /dev/null
    popd
}

build_tools() {
    pushd $toolkit_root
    echo "Building required tools..."
    make go-srpmpacker go-depsearch go-grapher go-specreader REBUILD_TOOLS=y > /dev/null
    popd
}

build_graph() {
    pushd $toolkit_root
    echo "Building dependency graph..."
    make workplan > /dev/null
    popd
}

# exit if not running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31mThis requires running as root\033[0m "
  exit
fi

script_dir=$(realpath $(dirname "${BASH_SOURCE[0]}"))
topdir=/usr/src/mariner
enable_local_repo=false

while (( "$#")); do
  case "$1" in
    -m ) mode="$2"; shift 2 ;;
    -v ) version="$2"; shift 2 ;;
    -p ) repo_path="$(realpath $2)"; shift 2 ;;
    -mo ) extra_mounts="$2"; shift 2 ;;
    -b ) build_mount_dir="$(realpath $2)"; shift 2;;
    -r ) enable_local_repo=true; shift ;;
    -h ) help; exit 1 ;;
    ? ) echo -e "ERROR: INVALID OPTION.\n\n"; help; exit 1 ;;
  esac
done

# Assign default values
[[ -z "${repo_path}" ]] && repo_path=${script_dir} && repo_path=${repo_path%'/toolkit'*}
[[ ! -d "${repo_path}" ]] && { print_error " Directory ${repo_path} does not exist"; exit 1; }
[[ -z "${mode}" ]] && mode="build"
[[ -z "${version}" ]] && version="2.0"

# Set relevant folder definitions using Mariner Makefile that can be overriden by user
# Default values are populated from toolkit/Makefile
PROJECT_ROOT=$repo_path
toolkit_root="$PROJECT_ROOT/toolkit"
pushd $toolkit_root
BUILD_DIR=$(make -s printvar-BUILD_DIR  2> /dev/null)              # default: $repo_path/build
OUT_DIR=$(make -s printvar-OUT_DIR 2> /dev/null)                   # default: $repo_path/out
SPECS_DIR=$(make -s printvar-SPECS_DIR 2> /dev/null)               # default: $repo_path/SPECS
BUILD_SRPMS_DIR=$(make -s printvar-BUILD_SRPMS_DIR 2> /dev/null)   # default: $repo_path/build/INTERMEDIATE_SRPMS
RPMS_DIR=$(make -s printvar-RPMS_DIR 2> /dev/null)                 # default: $repo_path/out/RPMS
TOOL_BINS_DIR=$(make -s printvar-TOOL_BINS_DIR 2> /dev/null)       # default: $repo_path/toolkit/out/tools
PKGBUILD_DIR=$(make -s printvar-PKGBUILD_DIR 2> /dev/null)         # default: $repo_path/build/pkg_artifacts
popd

# Assign remaining default values based on folder definitions
tmp_dir=${BUILD_DIR}/containerized-rpmbuild/tmp
mkdir -p ${tmp_dir}
[[ -z "${build_mount_dir}" ]] && build_mount_dir="$BUILD_DIR"
[[ ! -d "${build_mount_dir}" ]] && { print_error " Directory ${build_mount_dir} does not exist"; exit 1; }

cd "${script_dir}"  || { echo "ERROR: Could not change directory to ${script_dir}"; exit 1; }

# ==================== Setup ====================

# Get Mariner GitHub branch at $repo_path
repo_branch=$(git -C ${repo_path} rev-parse --abbrev-ref HEAD)

# Generate text based on mode (Use figlet to generate splash text once available on Mariner)
if [[ "${mode}" == "build" ]]; then
    echo -e "\033[31m -----------------------------------------------------------------------------------------\033[0m" > ${tmp_dir}/splash.txt
    echo -e "\033[31m ----------------------------------- MARINER BUILDER ! ----------------------------------- \033[0m" >> ${tmp_dir}/splash.txt
    echo -e "\033[31m -----------------------------------------------------------------------------------------\033[0m" >> ${tmp_dir}/splash.txt
else
    echo -e "\033[31m -----------------------------------------------------------------------------------------\033[0m" > ${tmp_dir}/splash.txt
    echo -e "\033[31m ----------------------------------- MARINER TESTER ! ------------------------------------ \033[0m" >> ${tmp_dir}/splash.txt
    echo -e "\033[31m -----------------------------------------------------------------------------------------\033[0m" >> ${tmp_dir}/splash.txt
fi

# ============ Populate SRPMS ============
# Populate ${repo_path}/build/INTERMEDIATE_SRPMS with SRPMs, that can be used to build RPMs in the container (only required in build mode)
if [[ "${mode}" == "build" ]]; then
    pushd $toolkit_root
    echo "Populating Intermediate SRPMs..."
    if [[ ( ! -f "$TOOL_BINS_DIR/srpmpacker" ) ]]; then build_tools; fi
    make input-srpms SRPM_FILE_SIGNATURE_HANDLING="update" > /dev/null
    popd
fi

# ============ Map chroot mount ============
if [[ "${mode}" == "build" ]]; then
    # Create a new directory and map it to chroot directory in container
    build_mount="${build_mount_dir}/container-build"
    buildroot_mount="${build_mount_dir}/container-buildroot"
    if [ -d "${build_mount}" ]; then rm -Rf ${build_mount}; fi
    if [ -d "${buildroot_mount}" ]; then rm -Rf ${buildroot_mount}; fi
    mkdir ${build_mount}
    mkdir ${buildroot_mount}
    mounts="${mounts} ${build_mount}:${topdir}/BUILD ${buildroot_mount}:${topdir}/BUILDROOT"
fi

# ============ Setup tools ============
# Copy relavant build tool executables from $TOOL_BINS_DIR
echo "Setting up tools..."
if [[ ( ! -f "$TOOL_BINS_DIR/depsearch" ) || ( ! -f "$TOOL_BINS_DIR/grapher" ) || ( ! -f "$TOOL_BINS_DIR/specreader" ) ]]; then build_tools; fi
if [[ ! -f "$PKGBUILD_DIR/graph.dot" ]]; then build_graph; fi
cp $TOOL_BINS_DIR/depsearch ${tmp_dir}/
cp $TOOL_BINS_DIR/grapher ${tmp_dir}/
cp $TOOL_BINS_DIR/specreader ${tmp_dir}/
cp $PKGBUILD_DIR/graph.dot ${tmp_dir}/

# ========= Setup mounts =========
echo "Setting up mounts..."

mounts="${mounts} $RPMS_DIR:/mnt/RPMS ${tmp_dir}:/mariner_setup_dir"
# Add extra 'build' mounts
if [[ "${mode}" == "build" ]]; then
    mounts="${mounts} $BUILD_SRPMS_DIR:/mnt/INTERMEDIATE_SRPMS $SPECS_DIR:${topdir}/SPECS"
fi

rm -f ${tmp_dir}/mounts.txt
for mount in $mounts $extra_mounts; do
    host_mount_path=$(realpath ${mount%%:*}) #remove suffix starting with ":"
    container_mount_path="${mount##*:}"      #remove prefix ending in ":"
    if [[ -d $host_mount_path ]]; then
        echo "$host_mount_path -> $container_mount_path"  >> "${tmp_dir}/mounts.txt"
        mount_arg=" $mount_arg -v '$host_mount_path:$container_mount_path' "
    else
        echo "WARNING: '$host_mount_path' does not exist. Skipping mount."
        echo "WARNING: '$host_mount_path' does not exist. Skipping mount."  >> "${tmp_dir}/mounts.txt"
    fi
done

# Copy resources into container
cp resources/welcome.txt $tmp_dir
sed -i "s~<REPO_PATH>~${repo_path}~" $tmp_dir/welcome.txt
sed -i "s~<REPO_BRANCH>~${repo_branch}~" $tmp_dir/welcome.txt
sed -i "s~<AARCH>~$(uname -m)~" $tmp_dir/welcome.txt
cp resources/setup_functions.sh $tmp_dir/setup_functions.sh
sed -i "s~<TOPDIR>~${topdir}~" $tmp_dir/setup_functions.sh

# ============ Build the dockerfile ============
dockerfile="${script_dir}/resources/mariner.Dockerfile"

if [[ "${mode}" == "build" ]]; then # Configure base image
    echo "Importing chroot into docker..."
    chroot_file="$BUILD_DIR/worker/worker_chroot.tar.gz"
    if [[ ! -f "${chroot_file}" ]]; then build_worker_chroot; fi
    chroot_hash=$(sha256sum "${chroot_file}" | cut -d' ' -f1)
    # Check if the chroot file's hash has changed since the last build
    if [[ ! -f "${tmp_dir}/hash" ]] || [[ "$(cat "${tmp_dir}/hash")" != "${chroot_hash}" ]]; then
        echo "Chroot file has changed, updating..."
        echo "${chroot_hash}" > "${tmp_dir}/hash"
        docker import "${chroot_file}" "mcr.microsoft.com/cbl-mariner/containerized-rpmbuild:${version}"
    else
        echo "Chroot is up-to-date"
    fi
    container_img="mcr.microsoft.com/cbl-mariner/containerized-rpmbuild:${version}"
else
    container_img="mcr.microsoft.com/cbl-mariner/base/core:${version}"
fi

# ================== Launch Container ==================
echo "Checking if build env is up-to-date..."
docker_image_tag="mcr.microsoft.com/cbl-mariner/${USER}-containerized-rpmbuild:${version}"
docker build -q \
                -f "${dockerfile}" \
                -t "${docker_image_tag}" \
                --build-arg container_img="$container_img" \
                --build-arg version="$version" \
                --build-arg enable_local_repo="$enable_local_repo" \
                --build-arg mariner_repo="$repo_path" \
                .

echo "docker_image_tag is ${docker_image_tag}"

bash -c "docker run --rm \
    ${mount_arg} \
    -it ${docker_image_tag} /bin/bash; \
    if [[ -d $RPMS_DIR/repodata ]]; then { rm -r $RPMS_DIR/repodata; echo 'Clearing repodata' ; }; fi
    "
