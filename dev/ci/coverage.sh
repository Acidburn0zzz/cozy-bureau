#!/bin/bash

set -ex

. "./dev/ci/start_xvfb.sh"

yarn test:unit:coverage --timeout $MOCHA_TIMEOUT --forbid-only
bash <(curl -s https://codecov.io/bash)
