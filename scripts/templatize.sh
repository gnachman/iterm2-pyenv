#!/bin/bash
set -x
(file "$3" | grep text) && sed -i "" -e "s,$1,__ITERM2_ENV__,g" -e "s,$2,__ITERM2_PYENV__,g" "$3"

