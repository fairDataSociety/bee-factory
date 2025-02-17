#!/bin/bash
MY_PATH=$(dirname "$0")
MY_PATH=$( cd "$MY_PATH" && pwd )
# Check used system variable set
BEE_ENV_PREFIX=$("$MY_PATH/utils/env-variable-value.sh" BEE_ENV_PREFIX)

NETWORK="$BEE_ENV_PREFIX-network"
NAME="$BEE_ENV_PREFIX-blockchain"
CONTAINER_IN_DOCKER=$(docker container ls -qaf name=$NAME)

if [ -z "$CONTAINER_IN_DOCKER" ]; then
  # necessary "-b 1" because anyway the Bee throws Error: waiting backend sync: Post "http://swarm-test-blockchain:9545": EOF
  docker run \
    -p 127.0.0.1:9545:9545 \
    --network $NETWORK \
    --name $NAME -d \
    trufflesuite/ganache-cli ganache-cli \
      -d -i 4020 -h 0.0.0.0 -p 9545 \
      -b 1 \
      --chainId 4020 \
      --db swarm-testchain --gasLimit 6721975
else
  docker start $NAME
fi
