#!/bin/sh
gdb -ex 'target remote :1234' "$@"
