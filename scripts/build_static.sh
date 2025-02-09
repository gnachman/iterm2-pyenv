#!/bin/bash
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

git checkout master
git pull origin master
export PATH=~/bin:$PWD/iterm2env/pyenv/plugins/python-build/bin:$PATH
export LD_FLAGS="-static"
export LINKFORSHARED=" "
export PYTHON_CONFIGURE_OPTS="--disable-shared"
SOURCE=$(pwd)/venv
RELDEST=iterm2env
DEST=$(pwd)/"$RELDEST"
BUILDS=$(pwd)/builds
ZIPNAME="iterm2env-$1.zip"
ZIPFILE="$BUILDS"/"$ZIPNAME"
URL="https://iterm2.com/downloads/pyenv/iterm2env-$1.zip"
MANIFEST="$BUILDS/manifest.json"
METADATANAME="iterm2env-metadata.json"
METADATA="$DEST"/"$METADATANAME"
PYENV_INSTALL="$DEST"/pyenv

#export LDFLAGS="-L$HOME/opt/zlib/lib -L$HOME/opt/sqlite/lib -L$HOME/opt/xz/lib -L$HOME/opt/gdbm/lib -lz"
#export CPPFLAGS="-I$HOME/opt/xz/include -I$HOME/opt/zlib/include -I$HOME/opt/sqlite/include -I$HOME/opt/gdbm/include"

rm -rf "$SOURCE"
rm -rf "$DEST"

# Note, you need to run 'brew update && brew upgrade pyenv' when bumping the
# python version. For some reason even when using the freshly checked out pyenv
# it still gets its list of versions from the system install.
PYTHON_VERSIONS=(3.7.4)

rm -rf "$PYENV_INSTALL"
mkdir -p "$PYENV_INSTALL"
git clone https://github.com/gnachman/pyenv.git "$PYENV_INSTALL"
pushd "$PYENV_INSTALL"
git checkout experiment
git log | head
git status
read xxx
popd

pushd /Users/gnachman/.pyenv
git pull
popd

export PYENV_ROOT=$SOURCE
ORIG_PATH="$PATH"
# If this fails complaining about missing a library like zlib, do: xcode-select --install
for PYTHON_VERSION in ${PYTHON_VERSIONS[@]}; do
    export PYENV_DEBUG=1

    echo Writing to log file
    rm -f /tmp/log3
    "$PYENV_INSTALL"/bin/pyenv install -v $PYTHON_VERSION | tee /tmp/log3 2>&1
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
sed -e "s/__VERSION__/$1/" \
    -e "s,__URL__,$URL," \
    -e "s,__SIGNATURE__,$SIGNATURE," \
    -e "s:__PYTHON_VERSIONS__:$(python_versions_json):" \
    < templates/manifest_template.json > "$MANIFEST"
git add "$ZIPFILE" "$MANIFEST"
git commit -am "Build version $1"
#git push origin master
