#!/bin/bash

STACKAGE_SNAPSHOTS="https://www.stackage.org/download/snapshots.json"
STACKAGE_BP_LTS="https://github.com/fpco/lts-haskell.git"
STACKAGE_BP_NIGHT="https://github.com/fpco/stackage-nightly.git"
HACKAGE_PKG_DIR="https://s3.amazonaws.com/hackage.fpcomplete.com/package"
HACKAGE_INDEX="https://s3.amazonaws.com/hackage.fpcomplete.com/00-index.tar.gz"

#exec > >(tee mirror_stackage.log) 2>&1
exec > >(tee mirror_stackage.log)

# Stackage ######################################################################
echo "mirroring Stackage..."

echo "downloading snapshots.json"
wget -N -nv -P "mirror" "$STACKAGE_SNAPSHOTS" 2>&1
if [ $? -ne 0 ]; then
    echo "error downloading snapshots.json"
    exit 1
fi
echo "done downloading snapshots.json"
echo

echo "downloading lts build plans"
if test -d "mirror/build-plans/lts-haskell"; then
    cd "mirror/build-plans/lts-haskell"
    git pull origin master
    if [ $? -ne 0 ]; then
        echo "error pulling repository of lts-haskell build plans"
        exit 2
    fi
    cd -
else
    git clone $STACKAGE_BP_LTS "mirror/build-plans/lts-haskell"
    if [ $? -ne 0 ]; then
        echo "error cloning repository of lts-haskell build plans"
        exit 3
    fi
fi
echo "done downloading lts build plans"
echo

echo "downloading nightly build plans"
if test -d "mirror/build-plans/stackage-nightly"; then
    cd "mirror/build-plans/stackage-nightly"
    git pull origin master
    if [ $? -ne 0 ]; then
        echo "error pulling repository of stackage-nightly build plans"
        exit 4
    fi
    cd -
else
    git clone $STACKAGE_BP_NIGHT "mirror/build-plans/stackage-nightly"
    if [ $? -ne 0 ]; then
        echo "error cloning repository of stackage-nightly build plans"
        exit 5
    fi
fi
echo "done downloading nightly build plans"
echo

# Hackage #######################################################################
echo "mirroring Hackage..."

echo "downloading package index"
wget -N -nv -P "mirror" "$HACKAGE_INDEX" 2>&1
if [ $? -ne 0 ]; then
    echo "error downloading package index"
    exit 6
fi
echo "done downloading package index"
echo

echo "producing list of packages urls to download"
HACKAGE_PKG_DIR_ESC=$(echo $HACKAGE_PKG_DIR | sed -e 's/[\/&]/\\&/g')

tar --list -f "mirror/$(basename $HACKAGE_INDEX)" \
| egrep "(.*)/([[:digit:].]+)/$" \
| sed "s/\(.*\)\/\(.*\)\/$/$HACKAGE_PKG_DIR_ESC\/\1-\2.tar.gz/" \
| sort -o download-packages-urls
if [ $? -ne 0 ]; then
    echo "error getting list of packages urls to download"
    exit 7
fi
echo "done getting list of packages urls to download"
echo

echo "downloading packages"
wget -nc -nv -i download-packages-urls --directory-prefix="mirror/packages" \
  -a download-packages-log
if [ $? -ne 0 ]; then
    echo "error downloading one or more packages"
else
    echo "done downloading packages"
fi
echo

echo "checking packages, re-download if corrupted"
touch checked-packages-urls
# producing a list of packages to check (never checked before)
comm -23 download-packages-urls checked-packages-urls > check-packages-urls
i=0
overall_count=$(wc -l check-packages-urls | cut -d' ' -f1)
while read line; do
    printf "\r%5u/%s" $i $overall_count 1>&2
    gzip --test "mirror/packages/$(basename $line)" 2>&1 \
    || wget -nv -O "mirror/packages/$(basename $line)" $line 2>&1 \
    || gzip --test "mirror/packages/$(basename $line)" 2>&1
    if [ $? -eq 0 ]; then
        echo $line >> checked-packages-urls-new
    fi
    ((i++))
done < check-packages-urls
mv checked-packages-urls checked-packages-urls-old
sort -m checked-packages-urls-old checked-packages-urls-new \
> checked-packages-urls

echo
echo "done checking and re-downloading packages"
echo

echo "finished"
exit 0
