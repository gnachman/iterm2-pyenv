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

rm -rf "$SOURCE"
rm -rf "$DEST"

PYTHON_VERSION=3.7.0

rm -rf "$PYENV_INSTALL"
mkdir -p "$PYENV_INSTALL"
git clone https://github.com/pyenv/pyenv.git "$PYENV_INSTALL"

pushd /Users/gnachman/.pyenv
git pull
popd

export PYENV_ROOT=$SOURCE
# If this fails complaining about missing a library like zlib, do: xcode-select --install
"$PYENV_INSTALL"/bin/pyenv install -v $PYTHON_VERSION
echo "Did this thing install $PYTHON_VERSION correctly in `pwd`?"
echo "If not you might have to run xcode-select --install"
read xxx
export PATH=$PYENV_ROOT/versions/$PYTHON_VERSION/bin:$PATH
yes | pip3 uninstall websockets
yes | pip3 uninstall protobuf
yes | pip3 uninstall iterm2
yes | pip3 uninstall aioconsole

pip3 install websockets
pip3 install protobuf
# pip really really wants to install old software. This seems to beat it into submission.
pip3 install --upgrade --force-reinstall --no-cache-dir iterm2
pip3 install --upgrade --force-reinstall --no-cache-dir iterm2
echo does this version look good?
read xxx
pip3 install aioconsole

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
sed -e "s/__VERSION__/$1/" < templates/metadata_template.json > "$METADATA"
zip -ry "$ZIPFILE" "$RELDEST"

SIGNATURE=$(openssl dgst -sha256 -sign $RSA_PRIVKEY "$ZIPFILE" | openssl enc -base64 -A)
sed -e "s/__VERSION__/$1/" -e "s,__URL__,$URL," -e "s,__SIGNATURE__,$SIGNATURE," < templates/manifest_template.json > "$MANIFEST"
git add "$ZIPFILE" "$MANIFEST"
git commit -am "Build version $1"
git push origin master
