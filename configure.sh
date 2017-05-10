#!/bin/bash

# Bluespec-related configuration

BLUESPECDIR=(YOUR_BLUESPEC_DIR)/lib
export BLUESPECDIR

BLUESPEC_HOME=(YOUR_BLUESPEC_DIR)
export BLUESPEC_HOME

export PATH=$PATH:$BLUESPEC_HOME/bin

BLUESPEC_LICENSE_FILE=(YOUR_BLUESPEC_LICENSE_DIR)/(YOUR_BLUESPEC_LICENSE_FILENAME.lic)
export BLUESPEC_LICENSE_FILE

# To avoid "stack overflow" errors

ulimit -s unlimited
