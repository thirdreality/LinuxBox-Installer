#!/bin/sh

set -e

cd ${SOURCE_DIR}

# @todo some of these options may be unncessary
export GYP_CROSSCOMPILE=1 \
    CC_target=aarch64-linux-gnu-gcc \
    CXX_target=aarch64-linux-gnu-g++ \
    npm_config_target_arch=arm64

pnpm install --frozen-lockfile
pnpm run build

if [ "$1" = "deploy" ]; then
    pnpm --filter=./ --legacy deploy ${BINARY_DIR}/pruned
fi
