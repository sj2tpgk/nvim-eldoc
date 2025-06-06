#!/bin/sh

cd "$(dirname "$0")" || exit
TERM=ansi xterm -fa 'Droid Sans Mono Dotted' -fs 32 -geometry 36x10 -e sh -c 'NVIM_APPNAME=app1 nvim -u init.vim test.py'
