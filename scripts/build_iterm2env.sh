#!/bin/bash
# optional:
#  setenv BUILD_DELTA 1
#  setenv RECORD_PREVIOUS 1
# Usage: build_iterm2env.sh version

function die {
  echo $1
  exit
}
if [ $# -ne 1 ]; then
   echo "Usage: build_iterm2env.sh VERSION"
   exit 1
fi
test -f "$RSA_PRIVKEY" || die "Set RSA_PRIVKEY environment variable to point at a valid private key (not set or nonexistent)"
set -x

if [ -n "$BUILD_DELTA" ]; then
    echo "Will build delta"
    read xxx
fi
if [ -n "$RECORD_PREVIOUS" ]; then
    echo "Will record previous"
    read xxx
fi

git checkout master
git pull origin master
export PATH=~/bin:$PWD/iterm2env/pyenv/plugins/python-build/bin:$PATH
export LD_FLAGS="-static"
export LINKFORSHARED=" "
export PYTHON_CONFIGURE_OPTS="--disable-shared"
unset MAKEFLAGS
VERSION="$1"
ROOT=$(pwd)
SOURCE=$ROOT/venv
RELDEST=iterm2env
DEST=$ROOT/"$RELDEST"
PREVIOUS=$ROOT/previous-iterm2env
PREVIOUS_VERSION=$ROOT/previous-version.txt
DELTA=$ROOT/delta
BUILDS=$ROOT/builds
ZIPNAME="iterm2env-$1.zip"
ZIPFILE="$BUILDS"/"$ZIPNAME"
DELTA_ZIP="$BUILDS"/"iterm2env-delta-$1.zip"
URL="https://iterm2.com/downloads/pyenv/iterm2env-$1.zip"
MANIFEST="$BUILDS/manifest.json"
METADATANAME="iterm2env-metadata.json"
METADATA="$DEST"/"$METADATANAME"
PYENV_INSTALL="$DEST"/pyenv

rm -rf "$SOURCE"
rm -rf "$DEST"

# Note, you need to run 'brew update && brew upgrade pyenv' when bumping the
# python version. For some reason even when using the freshly checked out pyenv
# it still gets its list of versions from the system install.
PYTHON_VERSIONS=(3.7.4)

rm -rf "$PYENV_INSTALL"
mkdir -p "$PYENV_INSTALL"
# Use my fork that builds only static libs to avoid pulling in system dependencies, such as on homebrew openssl.
git clone https://github.com/gnachman/pyenv.git "$PYENV_INSTALL"
pushd "$PYENV_INSTALL"
git checkout experiment
git log | head
git status
popd

pushd /Users/gnachman/.pyenv
git pull
popd

export PYENV_ROOT=$SOURCE
ORIG_PATH="$PATH"
# If this fails complaining about missing a library like zlib, do: xcode-select --install
for PYTHON_VERSION in ${PYTHON_VERSIONS[@]}; do
    "$PYENV_INSTALL"/bin/pyenv install -v $PYTHON_VERSION
    echo "Did this thing install $PYTHON_VERSION correctly in `pwd`?"
    echo "If not you might have to run xcode-select --install"
    read xxx
    export PATH=$PYENV_ROOT/versions/$PYTHON_VERSION/bin:$ORIG_PATH
    yes | pip3 uninstall websockets
    yes | pip3 uninstall protobuf
    yes | pip3 uninstall iterm2
    yes | pip3 uninstall aioconsole

    pip3 install websockets
    pip3 install protobuf
    # pip really really wants to install old software. This seems to beat it into submission.
    pip3 install --upgrade --force-reinstall --no-cache-dir iterm2
    pip3 install --upgrade --force-reinstall --no-cache-dir iterm2
    ITERM2_MODULE_VERSION=$(pip3 show iterm2 | egrep "^Version: " | sed -e "s/^Version: //")
    echo "I think I just installed version $ITERM2_MODULE_VERSION"
    echo does this version look good?
    echo if not run:
    echo $PYENV_ROOT/versions/$PYTHON_VERSION/bin/pip3 install --upgrade --force-reinstall --no-cache-dir iterm2
    echo Until it works. Sometimes it takes a while for the server to serve the newest version.
    read xxx
    pip3 install aioconsole
done

rsync $SOURCE/ $DEST/ -a --copy-links -v

function build_delta {
    echo About to build delta
    # Build delta update
    rm -rf "$DELTA"
    mkdir "$DELTA"
    rsync $SOURCE/ $DELTA/ -a --copy-links -v
    # Remove executable files, *.pyc, libraries, and miscellaneous others
    # because they are always different and are not intended to be included in
    # a delta update.
    find $DELTA -type f -perm +111 | xargs rm -f
    find $DELTA -name "*.pyc" | xargs rm -f
    rm -f $DELTA/versions/*/*/lib/*.a \
          $DELTA/versions/*/*/lib/*.a \
          $DELTA/versions/*/lib/*.a \
          $DELTA/versions/*/lib/*/_sysconfigdata* \
          $DELTA/versions/*/lib/*/config-*/* \


    # Remove unchanged files. This is the delta computation part.
    pushd $PREVIOUS
    find . -type f -exec $ROOT/scripts/rm_if_equal {} $DELTA/{} \;

    # The previous step left a bunch of empty directories behind. Remove them.
    find "$DELTA" -type d -empty -delete
    popd

    # Generate the metadata file.
    sed -e "s/__VERSION__/$1/" \
        -e "s/__ITERM2_MODULE_VERSION__/$ITERM2_MODULE_VERSION/" \
        < "$ROOT/templates/metadata_template.json" \
        > "$DELTA/$METADATANAME"

    # Make a zip file.
    HOLDER="$ROOT/holder"
    rm -rf $"HOLDER"
    mkdir $"HOLDER"
    mv $DELTA $"HOLDER/$RELDEST"
    pushd "$HOLDER"
    zip -ry "$DELTA_ZIP" "$RELDEST"
    popd

    echo Done building delta
}

function record_previous {
    rm -rf "$PREVIOUS"
    rsync $SOURCE/ $PREVIOUS/ -a --copy-links -v
}

if [ -n "$BUILD_DELTA" ]; then
    build_delta "$1"
fi
if [ -n "$RECORD_PREVIOUS" ]; then
    record_previous
    echo -n $VERSION > $PREVIOUS_VERSION
fi

fdupes -r -1 $DEST | while read line
do
  master=""
  for file in ${line[*]}
  do
    if [ "x${master}" == "x" ]
    then
      master=$file
    else
      ln -f "${master}" "${file}"
    fi
  done
done

find $DEST | grep -E '(__pycache__|\.pyc|\.pyo$)' | xargs rm -rf

rm -rf "$PYENV_INSTALL"/.git

# Hack the installed scripts to replace references to build paths with
# substitutable strings. The installer will need to replace these with the
# local paths after installation.
find $DEST -type f -exec scripts/templatize.sh "$SOURCE" "$PYENV_INSTALL" "{}" \;

rm -rf "$SOURCE"
sed -e "s/__VERSION__/$1/" -e "s/__ITERM2_MODULE_VERSION__/$ITERM2_MODULE_VERSION/" < templates/metadata_template.json > "$METADATA"
zip -ry "$ZIPFILE" "$RELDEST"

function python_versions_json {
    INTERMEDIATE=$(printf ", \"%s\"" "${PYTHON_VERSIONS[@]}")
    echo ${INTERMEDIATE:1}
}

SIGNATURE=$(openssl dgst -sha256 -sign $RSA_PRIVKEY "$ZIPFILE" | openssl enc -base64 -A)
SIZE=$(stat -f %z "$ZIPFILE")
if [ -z "$BUILD_DELTA" ]; then
    # Not a delta build
    sed -e "s/__VERSION__/$1/" \
        -e "s,__URL__,$URL," \
        -e "s,__SIZE__,$SIZE," \
        -e "s,__SIGNATURE__,$SIGNATURE," \
        -e "s:__PYTHON_VERSIONS__:$(python_versions_json):" \
        < templates/manifest_template.json > "$MANIFEST"
else
    # Delta build
    SITE_PACKAGES_URL="https://iterm2.com/downloads/pyenv/iterm2env-delta-$1.zip"
    SITE_PACKAGES_SIZE=$(stat -f %z "$DELTA_ZIP")
    SITE_PACKAGES_SIGNATURE=$(openssl dgst -sha256 -sign $RSA_PRIVKEY "$DELTA_ZIP" | openssl enc -base64 -A)
    PREVIOUS_VERSION=$(cat $PREVIOUS_VERSION)
    sed -e "s/__VERSION__/$1/" \
        -e "s,__URL__,$URL," \
        -e "s,__SIZE__,$SIZE," \
        -e "s,__SIGNATURE__,$SIGNATURE," \
        -e "s:__PYTHON_VERSIONS__:$(python_versions_json):" \
        -e "s,__SITE_PACKAGES_URL__,$SITE_PACKAGES_URL," \
        -e "s,__SITE_PACKAGES_SIZE__,$SITE_PACKAGES_SIZE," \
        -e "s,__SITE_PACKAGES_SIGNATURE__,$SITE_PACKAGES_SIGNATURE," \
        -e "s,__SITE_PACKAGES_FULL_MIN__,$PREVIOUS_VERSION," \
        -e "s,__SITE_PACKAGES_FULL_MAX__,$PREVIOUS_VERSION," \
        < templates/manifest_template_with_delta.json > "$MANIFEST"
    git add "$DELTA_ZIP"
fi
git add "$ZIPFILE" "$MANIFEST"
git commit -am "Build version $1"
#git push origin master
