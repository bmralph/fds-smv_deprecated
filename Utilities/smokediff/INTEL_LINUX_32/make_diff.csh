#!/bin/csh -f
source ../../../SMV_5/scripts/set_cfort.csh ia32
make -j4 -f ../Makefile intel_linux_32
