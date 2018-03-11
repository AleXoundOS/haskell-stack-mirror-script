#!/usr/bin/env bash

#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software Foundation,
#    Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

STACK_SETUP="https://raw.githubusercontent.com/fpco/stackage-content/\
master/stack/stack-setup-2.yaml"
STACKAGE_SNAPSHOTS="https://www.stackage.org/download/snapshots.json"
STACKAGE_BP_LTS="https://github.com/fpco/lts-haskell.git"
STACKAGE_BP_NIGHT="https://github.com/fpco/stackage-nightly.git"
HACKAGE_MIRROR="https://s3.amazonaws.com/hackage.fpcomplete.com/package"
HACKAGE_INDEX="https://s3.amazonaws.com/hackage.fpcomplete.com/01-index.tar.gz"

if test -z "$1"; then
    MIRROR_DIR="mirror"
else
    MIRROR_DIR="$1"
fi

if test -z "$2"; then
    MIRROR_URL="http://localhost:3000"
else
    MIRROR_URL="$2"
fi

if test -z "$3"; then
    JOBS_DOWNLOAD=4 #Defaulting to 4 parallel downloads if nproc does not exists
    command -v nproc 1>/dev/null 2>&1 && { JOBS_DOWNLOAD=$(nproc --all); }
else
    JOBS_DOWNLOAD=$3
fi

WGET="wget -nv" # non-verbose wget
exec > >(tee mirror.log) # 2>&1

# generating config.yaml
eval "cat <<EOF
$(< config.yaml.sh)
EOF" > config.yaml


# Stackage #####################################################################
echo "======= mirroring Stackage... ==========================================="

echo "======= downloading stack setup YAML ===================================="
$WGET -N -P "$MIRROR_DIR" "$STACK_SETUP" 2>&1 \
|| (echo "error downloading stack setup YAML" && exit 1)
MIRROR_URL_ESC=\
$(echo "$MIRROR_URL" | sed -e 's/[\/&]/\\&/g')
# replace part of url except it's basename in all urls from YAML
sed "s/\( \+url\: *\)\"http.*\/\([^?]*\).*\"\$/\1$MIRROR_URL_ESC\/stack\/\2/" \
  "$MIRROR_DIR/stack-setup-2.yaml" \
  > "$MIRROR_DIR/stack-setup-mirror.yaml"
echo


echo "======= producing list of stack setup files to download ================="
YAML="$MIRROR_DIR/$(basename $STACK_SETUP)"
REGEX_SHA1="sha1\: *\([[:xdigit:]]*\)"
: > download-stack-urls
: > download-stack-checksums
# get line numbers of url records in YAML and find nearby sha1
grep -E -n "url:( *)\"(.*)\"" "$YAML" \
  | cut -d':' -f1 \
  | while read -r line_number; do
        url=$(sed -n "${line_number}s/ \+url: *\"\(.*\)\"/\1/p" "$YAML")
        whitespace=$(sed -n "${line_number}s/\( \+\)url\: *\".*\"/\1/p" "$YAML")
        sha1=""

        # trying to find sha1 below
        line_below=$((line_number + 1))
        while test -z $sha1; do
            if test -z "$(sed -n "${line_below}s/\(${whitespace}\).*/\1/p" \
                          "$YAML")"; then
                break
            else
                sha1=$(sed -n "${line_below}s/${whitespace}$REGEX_SHA1/\1/p" \
                       "$YAML")
            fi
            ((++line_below))
        done

        # trying to find sha1 above
        line_above=$((line_number - 1))
        while test -z "$sha1"; do
            if test -z "$(sed -n "${line_above}s/\(${whitespace}\).*/\1/p" \
                          "$YAML")"; then
                break
            else
                sha1=$(sed -n "${line_above}s/${whitespace}$REGEX_SHA1/\1/p" \
                       "$YAML")
            fi
            ((--line_above))
        done

        echo "$url" >> download-stack-urls
        if test -z "$sha1"; then
            echo "could not get sha1 for $url ($YAML:$line_number)"
        else
            echo "$sha1  $MIRROR_DIR/stack/$(basename "$url" | cut -d'?' -f1)" \
              >> download-stack-checksums
        fi
    done
sort -u download-stack-checksums -o download-stack-checksums-sorted
mv download-stack-checksums-sorted download-stack-checksums
echo


echo "======= downloading stack setup files ==================================="
$WGET -nc -i download-stack-urls --directory-prefix="$MIRROR_DIR/stack" 2>&1 \
  | (>&2 tee download-stack.log) \
|| echo "error downloading one or more stack setup files"
# truncate filenames with '?'
for filename in "$MIRROR_DIR/stack/"*; do
    if [[ $filename == *\?* ]]; then
        mv -v "$filename" \
           "$(echo "$filename" | sed -n 's/\([^?]*\)\?.*/\1/p')"
    fi
done
echo


echo "======= checking stack setup files ======================================"
touch checked-stack-checksums
comm -23 download-stack-checksums checked-stack-checksums \
  > check-stack-checksums
: > checked-stack-checksums-new
i=0
overall_count=$(wc -l check-stack-checksums | cut -d' ' -f1)
while read -r line; do
    printf "\r%3u/%s" $i "$overall_count" 1>&2
    if "$line" | sha1sum -c --quiet
    then
        echo "$line" >> checked-stack-checksums-new
    else
        echo "corrupted stack setup file: $(echo "$line" | cut -d' ' -f1)"
        rm -fv "$line"
        echo "run the script again to try to re-download it"
    fi
    ((++i))
done < check-stack-checksums
mv checked-stack-checksums checked-stack-checksums-old
sort -m checked-stack-checksums-old checked-stack-checksums-new \
  -o checked-stack-checksums
echo


echo "======= downloading snapshots.json ======================================"
if ! $WGET -N -P "$MIRROR_DIR" "$STACKAGE_SNAPSHOTS" 2>&1
then
    echo "error downloading snapshots.json"
    exit 2
fi
echo


echo "======= downloading lts build plans ====================================="
if test -d "$MIRROR_DIR/build-plans/lts-haskell"; then
    if ! cd "$MIRROR_DIR/build-plans/lts-haskell"
    then
        echo "error changing directory to " \
             "\"$MIRROR_DIR/build-plans/lts-haskell\"!"
        exit 9
    fi
    if ! git pull origin master
    then
        echo "error pulling repository of lts-haskell build plans"
        exit 3
    fi
    if ! cd -
    then
        echo "error changing directory to \"$HOME\"!"
        exit 10
    fi
else
    if ! git clone $STACKAGE_BP_LTS "$MIRROR_DIR/build-plans/lts-haskell"
    then
        echo "error cloning repository of lts-haskell build plans"
        exit 4
    fi
fi
echo


echo "======= downloading nightly build plans ================================="
if test -d "$MIRROR_DIR/build-plans/stackage-nightly"; then
    if ! cd "$MIRROR_DIR/build-plans/stackage-nightly"
    then
        echo "error changing directory to " \
             "\"$MIRROR_DIR/build-plans/stackage-nightly\"!"
        exit 11
    fi

    if ! git pull origin master
    then
        echo "error pulling repository of stackage-nightly build plans"
        exit 5
    fi
    if ! cd -
    then
        echo "error changing directory to \"$HOME\"!"
        exit 12
    fi
else
    if ! git clone $STACKAGE_BP_NIGHT "$MIRROR_DIR/build-plans/stackage-nightly"
    then
        echo "error cloning repository of stackage-nightly build plans"
        exit 6
    fi
fi
echo

# Hackage ######################################################################
echo "======= mirroring Hackage... ============================================"

echo "======= downloading package index ======================================="
if ! $WGET -N -P "$MIRROR_DIR" "$HACKAGE_INDEX" 2>&1
then
    echo "error downloading package index"
    exit 7
fi
echo


echo "======= producing list of packages urls to download ====================="
HACKAGE_MIRROR_ESC=$(echo $HACKAGE_MIRROR | sed -e 's/[\/&]/\\&/g')

if ! tar --list -f "$MIRROR_DIR/$(basename $HACKAGE_INDEX)" \
        | grep -E -o "(.*)/([[:digit:].]+)/" \
        | sed "s/\(.*\)\/\(.*\)\/$/$HACKAGE_MIRROR_ESC\/\1-\2.tar.gz/" \
        | sort -u -o download-packages-urls
then
    echo "error getting list of packages urls to download"
    exit 8
fi
echo


echo "======= downloading packages ============================================"
cat download-packages-urls | xargs -n 1 -P $JOBS_DOWNLOAD $WGET \
  -nc --directory-prefix="$MIRROR_DIR/packages" 2>&1 \
    | (>&2 tee download-packages.log) \
    || (echo "error downloading one or more packages")
echo


echo "======= checking packages ==============================================="
sed -n 's/.*\/\(.*.tar.gz\)/\1/p' download-packages-urls \
  > download-packages-files
touch checked-packages-files
# producing a list of packages to check (not checked before)
comm -23 download-packages-files checked-packages-files \
  > check-packages-files
: > checked-packages-files-new
i=0
overall_count=$(wc -l check-packages-files | cut -d' ' -f1)
while read -r line; do
    printf "\r%5u/%s" $i "$overall_count" 1>&2
    if gzip --test "$MIRROR_DIR/packages/$line"
    then
        echo "$line" >> checked-packages-files-new
    else
        echo "corrupted or missing package file: $line"
        rm -fv "$MIRROR_DIR/packages/$line"
        echo "run the script again to try to re-download it"
    fi
    ((++i))
done < check-packages-files
mv checked-packages-files checked-packages-files-old
sort -m checked-packages-files-old checked-packages-files-new \
  -o checked-packages-files
echo

echo "finished"
exit 0
