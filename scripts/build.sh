#!/bin/bash
#
# This file is part of MagiskOnWSALocal.
#
# MagiskOnWSALocal is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# MagiskOnWSALocal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with MagiskOnWSALocal.  If not, see <https://www.gnu.org/licenses/>.
#
# Copyright (C) 2023 LSPosed Contributors
#

if [ ! "$BASH_VERSION" ]; then
    echo "Please do not use sh to run this script, just execute it directly" 1>&2
    exit 1
fi
HOST_ARCH=$(uname -m)
if [ "$HOST_ARCH" != "x86_64" ] && [ "$HOST_ARCH" != "aarch64" ]; then
    echo "Unsupported architectures: $HOST_ARCH"
    exit 1
fi
cd "$(dirname "$0")" || exit 1
# export TMPDIR=$HOME/.cache/wsa
if [ "$TMPDIR" ] && [ ! -d "$TMPDIR" ]; then
    mkdir -p "$TMPDIR"
fi
WORK_DIR=$(mktemp -d -t wsa-build-XXXXXXXXXX_) || exit 1

DOWNLOAD_DIR=../download
DOWNLOAD_CONF_NAME=download.list
PYTHON_VENV_DIR="$(dirname "$PWD")/python3-env"

dir_clean() {
    rm -rf "${WORK_DIR:?}"
    if [ "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
        echo "Cleanup Temp Directory"
        rm -rf "${TMPDIR:?}"
        unset TMPDIR
    fi
    rm -f "${DOWNLOAD_DIR:?}/$DOWNLOAD_CONF_NAME"
    if [ "$(python3 -c 'import sys ; print( 1 if sys.prefix != sys.base_prefix else 0 )')" = "1" ]; then
        echo "deactivate python3 venv"
        deactivate
    fi
}
trap dir_clean EXIT
OUTPUT_DIR=../output
WSA_WORK_ENV="${WORK_DIR:?}/ENV"
if [ -f "$WSA_WORK_ENV" ]; then rm -f "${WSA_WORK_ENV:?}"; fi
touch "$WSA_WORK_ENV"
export WSA_WORK_ENV
clean_download() {
    if [ -d "$DOWNLOAD_DIR" ]; then
        echo "Cleanup Download Directory"
        if [ "$CLEAN_DOWNLOAD_WSA" ]; then
            rm -f "${WSA_ZIP_PATH:?}"
        fi
        if [ "$CLEAN_DOWNLOAD_MAGISK" ]; then
            rm -f "${MAGISK_PATH:?}"
        fi
        if [ "$CLEAN_DOWNLOAD_GAPPS" ]; then
            rm -f "${GAPPS_PATH:?}"
        fi
        if [ "$CLEAN_DOWNLOAD_KERNELSU" ]; then
            rm -f "${KERNELSU_PATH:?}"
            rm -f "${KERNELSU_INFO:?}"
        fi
    fi
}
abort() {
    [ "$1" ] && echo -e "ERROR: $1"
    echo "Build: an error has occurred, exit"
    if [ -d "$WORK_DIR" ]; then
        echo -e "\nCleanup Work Directory"
        dir_clean
    fi
    clean_download
    exit 1
}
trap abort INT TERM

default() {
    ARCH=x64
    RELEASE_TYPE=retail
    MAGISK_VER=stable
    ROOT_SOL=magisk
}

exit_with_message() {
    echo "ERROR: $1"
    usage
    exit 1
}

ARCH_MAP=(
    "x64"
    "arm64"
)

RELEASE_TYPE_MAP=(
    "retail"
    "RP"
    "WIS"
    "WIF"
)

MAGISK_VER_MAP=(
    "stable"
    "beta"
    "canary"
    "debug"
    "release"
)

ROOT_SOL_MAP=(
    "magisk"
    "kernelsu"
    "none"
)

COMPRESS_FORMAT_MAP=(
    "7z"
    "zip"
)

ARR_TO_STR() {
    local arr=("$@")
    local joined
    printf -v joined "%s, " "${arr[@]}"
    echo "${joined%, }"
}

usage() {
    default
    echo -e "
Usage:
    --arch              Architecture of WSA.

                        Possible values: $(ARR_TO_STR "${ARCH_MAP[@]}")
                        Default: $ARCH

    --release-type      Release type of WSA.
                        RP means Release Preview, WIS means Insider Slow, WIF means Insider Fast.

                        Possible values: $(ARR_TO_STR "${RELEASE_TYPE_MAP[@]}")
                        Default: $RELEASE_TYPE

    --magisk-ver        Magisk version.

                        Possible values: $(ARR_TO_STR "${MAGISK_VER_MAP[@]}")
                        Default: $MAGISK_VER

    --root-sol          Root solution.
                        \"none\" means no root.

                        Possible values: $(ARR_TO_STR "${ROOT_SOL_MAP[@]}")
                        Default: $ROOT_SOL

    --compress-format
                        Compress format of output file.
                        If this option is not specified and --compress is not specified, the generated file will not be compressed

                        Possible values: $(ARR_TO_STR "${COMPRESS_FORMAT_MAP[@]}")

Additional Options:
    --compress          Compress the WSA, The default format is 7z, you can use the format specified by --compress-format
    --offline           Build WSA offline
    --magisk-custom     Install custom Magisk
    --skip-download-wsa Skip download WSA
    --debug             Debug build mode
    --help              Show this help message and exit

Example:
    ./build.sh --release-type RP --magisk-ver beta
    ./build.sh --arch arm64 --release-type WIF
    ./build.sh --release-type WIS
    ./build.sh --offline --magisk-custom
    ./build.sh --release-type WIF --magisk-custom --magisk-ver release
    "
}

ARGUMENT_LIST=(
    "arch:"
    "release-type:"
    "magisk-ver:"
    "nofix-props"
    "root-sol:"
    "compress-format:"
    "remove-amazon"
    "compress"
    "offline"
    "magisk-custom"
    "debug"
    "help"
    "skip-download-wsa"
    "install-gapps"
)

default

opts=$(
    getopt \
        --longoptions "$(printf "%s," "${ARGUMENT_LIST[@]}")" \
        --name "$(basename "$0")" \
        --options "" \
        -- "$@"
) || exit_with_message "Failed to parse options, please check your input"

eval set --"$opts"
while [[ $# -gt 0 ]]; do
   case "$1" in
        --arch              ) ARCH="$2"; shift 2 ;;
        --release-type      ) RELEASE_TYPE="$2"; shift 2 ;;
        --install-gapps     ) HAS_GAPPS=true; shift 2 ;;
        --root-sol          ) ROOT_SOL="$2"; shift 2 ;;
        --compress-format   ) COMPRESS_FORMAT="$2"; shift 2 ;;
        --compress          ) COMPRESS_OUTPUT="yes"; shift ;;
        --offline           ) OFFLINE="on"; shift ;;
        --magisk-custom     ) CUSTOM_MAGISK="debug"; shift ;;
        --magisk-ver        ) MAGISK_VER="$2"; shift 2 ;;
        --debug             ) DEBUG="on"; shift ;;
        --skip-download-wsa ) DOWN_WSA="no"; shift ;;
        --help              ) usage; exit 0 ;;
        --                  ) shift; break;;
   esac
done

if [ "$CUSTOM_MAGISK" ]; then
    if [ -z "$MAGISK_VER" ]; then
        MAGISK_VER=$CUSTOM_MAGISK
    fi
fi

check_list() {
    local input=$1
    if [ -n "$input" ]; then
        local name=$2
        shift
        local arr=("$@")
        local list_count=${#arr[@]}
        for i in "${arr[@]}"; do
            if [ "$input" == "$i" ]; then
                echo "INFO: $name: $input"
                break
            fi
            ((list_count--))
            if (("$list_count" <= 0)); then
                exit_with_message "Invalid $name: $input"
            fi
        done
    fi
}

check_list "$ARCH" "Architecture" "${ARCH_MAP[@]}"
check_list "$RELEASE_TYPE" "Release Type" "${RELEASE_TYPE_MAP[@]}"
check_list "$MAGISK_VER" "Magisk Version" "${MAGISK_VER_MAP[@]}"
check_list "$ROOT_SOL" "Root Solution" "${ROOT_SOL_MAP[@]}"
check_list "$COMPRESS_FORMAT" "Compress Format" "${COMPRESS_FORMAT_MAP[@]}"

if [ "$DEBUG" ]; then
    set -x
fi

require_su() {
    if test "$(id -u)" != "0"; then
        if [ "$(sudo id -u)" != "0" ]; then
            abort "sudo is required to run this script"
        fi
    fi
}
# shellcheck disable=SC1091
[ -f "$PYTHON_VENV_DIR/bin/activate" ] && {
    source "$PYTHON_VENV_DIR/bin/activate" || abort "Failed to activate virtual environment, please re-run install_deps.sh"
}
declare -A RELEASE_NAME_MAP=(["retail"]="Retail" ["RP"]="Release Preview" ["WIS"]="Insider Slow" ["WIF"]="Insider Fast")
declare -A ANDROID_API_MAP=(["30"]="11.0" ["32"]="12.1" ["33"]="13.0")
RELEASE_NAME=${RELEASE_NAME_MAP[$RELEASE_TYPE]} || abort

echo -e "Build: RELEASE_TYPE=$RELEASE_NAME"

WSA_ZIP_PATH=$DOWNLOAD_DIR/wsa-$RELEASE_TYPE.zip
vclibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00_$ARCH.appx"
UWPVCLibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00.UWPDesktop_$ARCH.appx"
xaml_PATH="$DOWNLOAD_DIR/Microsoft.UI.Xaml.2.8_$ARCH.appx"
MAGISK_ZIP=magisk-$MAGISK_VER.zip
MAGISK_PATH=$DOWNLOAD_DIR/$MAGISK_ZIP
if [ "$CUSTOM_MAGISK" ]; then
    if [ ! -f "$MAGISK_PATH" ]; then
        echo "Custom Magisk $MAGISK_ZIP not found"
        MAGISK_ZIP=app-$MAGISK_VER.apk
        echo "Fallback to $MAGISK_ZIP"
        MAGISK_PATH=$DOWNLOAD_DIR/$MAGISK_ZIP
        if [ ! -f "$MAGISK_PATH" ]; then
            abort "Custom Magisk $MAGISK_ZIP not found\nPlease put custom Magisk in $DOWNLOAD_DIR"
        fi
    fi
fi
ANDROID_API=33
update_gapps_file_name() {
    GAPPS_FILE_NAME=GApps-$ARCH-${ANDROID_API_MAP[$ANDROID_API]}.apex
    GAPPS_PATH=$DOWNLOAD_DIR/$GAPPS_FILE_NAME
}
WSA_MAJOR_VER=0
update_ksu_zip_name() {
    KERNEL_VER=""
    case "$WSA_MAJOR_VER" in
      "2305") KERNEL_VER="5.15.94.2";;
      "2306") KERNEL_VER="5.15.104.1";;
      "2307") KERNEL_VER="5.15.104.2";;
      "2308") KERNEL_VER="5.15.104.3";;
      "2309") KERNEL_VER="5.15.104.4";;
      *) abort "KernelSU is not supported in this WSA version: $WSA_MAJOR_VER"
    esac
    KERNELSU_ZIP_NAME=kernelsu-$ARCH-$KERNEL_VER.zip
    KERNELSU_PATH=$DOWNLOAD_DIR/$KERNELSU_ZIP_NAME
    KERNELSU_INFO="$KERNELSU_PATH.info"
}
if [ -z ${OFFLINE+x} ]; then
    require_su
    if [ "$DOWN_WSA" != "no" ]; then
        echo "Generate Download Links"
        python3 generateWSALinks.py "$ARCH" "$RELEASE_TYPE" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
    else
        echo "Generate Download Links"
        python3 generateWSALinks.py "$ARCH" "$RELEASE_TYPE" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$DOWN_WSA" || abort
        WSA_MAJOR_VER=$(python3 getWSAMajorVersion.py "$ARCH" "$WSA_ZIP_PATH")
    fi
    if [[ "$WSA_MAJOR_VER" -lt 2211 ]]; then
        ANDROID_API=32
    fi
    if [ "$ROOT_SOL" = "magisk" ]; then
        if [ -z ${CUSTOM_MAGISK+x} ]; then
            python3 generateMagiskLink.py "$MAGISK_VER" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
        fi
    fi
    if [ "$ROOT_SOL" = "kernelsu" ]; then
        update_ksu_zip_name
        python3 generateKernelSULink.py "$ARCH" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$KERNEL_VER" "$KERNELSU_ZIP_NAME" || abort
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
        # shellcheck disable=SC2153
        echo "KERNELSU_VER=$KERNELSU_VER" >"$KERNELSU_INFO"
    fi
    if [ "$HAS_GAPPS" ]; then
        update_gapps_file_name
        python3 generateGappsLink.py "$ARCH" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$ANDROID_API" "$GAPPS_FILE_NAME" || abort
    fi

    echo "Download Artifacts"
    if ! aria2c --no-conf --log-level=info --log="$DOWNLOAD_DIR/aria2_download.log" -x16 -s16 -j5 -c -R -m0 --async-dns=false --check-integrity=true --continue=true --allow-overwrite=true --conditional-get=true -d"$DOWNLOAD_DIR" -i"$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME"; then
        echo "We have encountered an error while downloading files."
        exit 1
    fi
else # Offline mode
    WSA_MAJOR_VER=$(python3 getWSAMajorVersion.py "$ARCH" "$WSA_ZIP_PATH")
    if [[ "$WSA_MAJOR_VER" -lt 2211 ]]; then
        ANDROID_API=32
    fi
    declare -A FILES_CHECK_LIST=([WSA_ZIP_PATH]="$WSA_ZIP_PATH" [xaml_PATH]="$xaml_PATH" [vclibs_PATH]="$vclibs_PATH" [UWPVCLibs_PATH]="$UWPVCLibs_PATH")
    if [ "$ROOT_SOL" = "magisk" ]; then
        FILES_CHECK_LIST+=(["MAGISK_PATH"]="$MAGISK_PATH")
    fi
    if [ "$ROOT_SOL" = "kernelsu" ]; then
        update_ksu_zip_name
        FILES_CHECK_LIST+=(["KERNELSU_PATH"]="$KERNELSU_PATH")
    fi
    if [ "$HAS_GAPPS" ]; then
        update_gapps_file_name
        FILES_CHECK_LIST+=(["GAPPS_PATH"]="$GAPPS_PATH")
    fi
    for i in "${FILES_CHECK_LIST[@]}"; do
        if [ ! -f "$i" ]; then
            echo "Offline mode: missing [$i]."
            OFFLINE_ERR="1"
        fi
    done
    if [ "$OFFLINE_ERR" ]; then
        echo "Offline mode: Some files are missing, please disable offline mode."
        exit 1
    fi
    require_su
fi

echo "Extract WSA"
if [ -f "$WSA_ZIP_PATH" ]; then
    if ! python3 extractWSA.py "$ARCH" "$WSA_ZIP_PATH" "$WORK_DIR" "$WSA_WORK_ENV"; then
        CLEAN_DOWNLOAD_WSA=1
        abort "Unzip WSA failed, is the download incomplete?"
    fi
    echo -e "Extract done\n"
    # shellcheck disable=SC1090
    source "$WSA_WORK_ENV" || abort
else
    echo "The WSA zip package does not exist, is the download incomplete?"
    exit 1
fi

if [ "$ROOT_SOL" = "magisk" ]; then
    echo "Extract Magisk"
    if [ -f "$MAGISK_PATH" ]; then
        MAGISK_VERSION_NAME=""
        MAGISK_VERSION_CODE=0
        if ! python3 extractMagisk.py "$ARCH" "$MAGISK_PATH" "$WORK_DIR"; then
            CLEAN_DOWNLOAD_MAGISK=1
            abort "Unzip Magisk failed, is the download incomplete?"
        fi
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
        if [ "$MAGISK_VERSION_CODE" -lt 26000 ] && [ "$MAGISK_VER" != "stable" ] && [ -z ${CUSTOM_MAGISK+x} ]; then
            abort "Please install Magisk 26.0+"
        fi
        sudo chmod +x "../linker/$HOST_ARCH/linker64" || abort
        sudo patchelf --set-interpreter "../linker/$HOST_ARCH/linker64" "$WORK_DIR/magisk/magiskpolicy" || abort
        chmod +x "$WORK_DIR/magisk/magiskpolicy" || abort
        chmod +x "$WORK_DIR/magisk/magiskboot" || abort
    elif [ -z "${CUSTOM_MAGISK+x}" ]; then
        echo "The Magisk zip package does not exist, is the download incomplete?"
        exit 1
    else
        echo "The Magisk zip package does not exist, rename it to magisk-debug.zip and put it in the download folder."
        exit 1
    fi
    echo -e "done\n"
fi

if [ "$ROOT_SOL" = "kernelsu" ]; then
    update_ksu_zip_name
    echo "Extract KernelSU"
    # shellcheck disable=SC1090
    source "${KERNELSU_INFO:?}" || abort
    if ! unzip "$KERNELSU_PATH" -d "$WORK_DIR/kernelsu"; then
        CLEAN_DOWNLOAD_KERNELSU=1
        abort "Unzip KernelSU failed, package is corrupted?"
    fi
    if [ "$ARCH" = "x64" ]; then
        mv "$WORK_DIR/kernelsu/bzImage" "$WORK_DIR/kernelsu/kernel"
    elif [ "$ARCH" = "arm64" ]; then
        mv "$WORK_DIR/kernelsu/Image" "$WORK_DIR/kernelsu/kernel"
    fi
    echo -e "done\n"
fi

if [ "$ROOT_SOL" = 'magisk' ]; then
    echo "Integrate Magisk"
    "$WORK_DIR/magisk/magiskboot" compress=xz "$WORK_DIR/magisk/magisk64" "$WORK_DIR/magisk/magisk64.xz"
    "$WORK_DIR/magisk/magiskboot" compress=xz "$WORK_DIR/magisk/magisk32" "$WORK_DIR/magisk/magisk32.xz"
    "$WORK_DIR/magisk/magiskboot" compress=xz "$WORK_DIR/magisk/stub.apk" "$WORK_DIR/magisk/stub.xz"
    echo "KEEPFORCEENCRYPT=true" >> "$WORK_DIR/magisk/config"
    echo "PREINITDEVICE=sde" >> "$WORK_DIR/magisk/config"
    "$WORK_DIR/magisk/magiskboot" cpio "$WORK_DIR/wsa/$ARCH/Tools/initrd.img" "mv /init /wsainit" "add 0750 /lspinit ../bin/$ARCH/lspinit" "ln /lspinit /init" "add 0750 /magiskinit $WORK_DIR/magisk/magiskinit" "mkdir 0750 overlay.d" "mkdir 0750 overlay.d/sbin" "add 0644 overlay.d/sbin/magisk64.xz $WORK_DIR/magisk/magisk64.xz" "add 0644 overlay.d/sbin/magisk32.xz $WORK_DIR/magisk/magisk32.xz" "add 0644 overlay.d/sbin/stub.xz $WORK_DIR/magisk/stub.xz" "mkdir 000 .backup" "add 000 .backup/.magisk $WORK_DIR/magisk/config" || abort "Unable to patch initrd"
    echo -e "Integrate Magisk done\n"
elif [ "$ROOT_SOL" = "kernelsu" ]; then
    echo "Integrate KernelSU"
    mv "$WORK_DIR/wsa/$ARCH/Tools/kernel" "$WORK_DIR/wsa/$ARCH/Tools/kernel_origin"
    cp "$WORK_DIR/kernelsu/kernel" "$WORK_DIR/wsa/$ARCH/Tools/kernel"
    echo -e "Integrate KernelSU done\n"
fi

echo "Remove signature and add scripts"
sudo rm -rf "${WORK_DIR:?}"/wsa/"$ARCH"/\[Content_Types\].xml "$WORK_DIR/wsa/$ARCH/AppxBlockMap.xml" "$WORK_DIR/wsa/$ARCH/AppxSignature.p7x" "$WORK_DIR/wsa/$ARCH/AppxMetadata" || abort
cp "$vclibs_PATH" "$xaml_PATH" "$WORK_DIR/wsa/$ARCH" || abort
cp "$UWPVCLibs_PATH" "$xaml_PATH" "$WORK_DIR/wsa/$ARCH" || abort
cp "../bin/$ARCH/makepri.exe" "$WORK_DIR/wsa/$ARCH" || abort
cp "../xml/priconfig.xml" "$WORK_DIR/wsa/$ARCH/xml/" || abort
cp ../installer/MakePri.ps1 "$WORK_DIR/wsa/$ARCH" || abort
cp ../installer/Install.ps1 "$WORK_DIR/wsa/$ARCH" || abort
cp ../installer/Run.bat "$WORK_DIR/wsa/$ARCH" || abort
find "$WORK_DIR/wsa/$ARCH" -maxdepth 1 -mindepth 1 -printf "%P\n" >"$WORK_DIR/wsa/$ARCH/filelist.txt" || abort
echo -e "Remove signature and add scripts done\n"

echo "Generate info"

if [[ "$ROOT_SOL" = "none" ]]; then
    name1=""
elif [ "$ROOT_SOL" = "magisk" ]; then
    name1="-with-magisk-$MAGISK_VERSION_NAME($MAGISK_VERSION_CODE)-$MAGISK_VER"
elif [ "$ROOT_SOL" = "kernelsu" ]; then
    name1="-with-$ROOT_SOL-$KERNELSU_VER"
fi
if [ -z "$HAS_GAPPS" ]; then
    name2="-NoGApps"
else
    name2=-GApps-${ANDROID_API_MAP[$ANDROID_API]}
fi
artifact_name=WSA_${WSA_VER}_${ARCH}_${WSA_REL}${name1}${name2}

echo "$artifact_name"
echo -e "\nFinishing building...."
if [ -f "$OUTPUT_DIR" ]; then
    sudo rm -rf ${OUTPUT_DIR:?}
fi
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
OUTPUT_PATH="${OUTPUT_DIR:?}/$artifact_name"
if [ "$COMPRESS_OUTPUT" ] || [ -n "$COMPRESS_FORMAT" ]; then
    mv "$WORK_DIR/wsa/$ARCH" "$WORK_DIR/wsa/$artifact_name"
    if [ -z "$COMPRESS_FORMAT" ]; then
        COMPRESS_FORMAT="7z"
    fi
    if [ -n "$COMPRESS_FORMAT" ]; then
        FILE_EXT=".$COMPRESS_FORMAT"
        OUTPUT_PATH="$OUTPUT_PATH$FILE_EXT"
    fi
    rm -f "${OUTPUT_PATH:?}" || abort
    if [ "$COMPRESS_FORMAT" = "7z" ]; then
        echo "Compressing with 7z"
        7z a "${OUTPUT_PATH:?}" "$WORK_DIR/wsa/$artifact_name" || abort
    elif [ "$COMPRESS_FORMAT" = "zip" ]; then
        echo "Compressing with zip"
        7z -tzip a "$OUTPUT_PATH" "$WORK_DIR/wsa/$artifact_name" || abort
    fi
else
    rm -rf "${OUTPUT_PATH:?}" || abort
    cp -r "$WORK_DIR/wsa/$ARCH" "$OUTPUT_PATH" || abort
fi
echo -e "done\n"

echo "Cleanup Work Directory"
sudo rm -rf "${WORK_DIR:?}"
echo "done"
