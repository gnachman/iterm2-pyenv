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
DEST=iterm2env
BUILDS=builds
ZIPNAME="iterm2env-$1.zip"
ZIPFILE="$BUILDS"/"$ZIPNAME"
URL="https://iterm2.com/downloads/pyenv/iterm2env-$1.zip"
MANIFEST="$BUILDS/manifest.json"
METADATANAME="iterm2env-metadata.json"
METADATA="$DEST"/"$METADATANAME"

rm -rf "$SOURCE"

PYTHON_VERSION=3.6.5

rm -rf /tmp/pyenv
git clone https://github.com/pyenv/pyenv.git /tmp/pyenv
export PYENV_ROOT=$SOURCE
# If this fails complaining about missing a library like zlib, do: xcode-select --install
/tmp/pyenv/bin/pyenv install $PYTHON_VERSION
export PATH=$PYENV_ROOT/versions/$PYTHON_VERSION/bin:$PATH
yes | pip3 uninstall websockets
yes | pip3 uninstall protobuf
yes | pip3 uninstall iterm2

pip3 install websockets
pip3 install protobuf
pip3 install iterm2

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
rm -rf "$SOURCE"
sed -e "s/__VERSION__/$1/" < templates/metadata_template.json > "$METADATA"
zip -ry "$ZIPFILE" "$DEST"
rm -rf "$DEST"

SIGNATURE=$(openssl dgst -sha256 -sign $RSA_PRIVKEY "$ZIPFILE" | openssl enc -base64 -A)
sed -e "s/__VERSION__/$1/" -e "s,__URL__,$URL," -e "s,__SIGNATURE__,$SIGNATURE," < templates/manifest_template.json > "$MANIFEST"
git add "$ZIPFILE" "$MANIFEST"
git commit -am "Build version $1"
git push origin master
