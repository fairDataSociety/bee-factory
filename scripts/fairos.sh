#!/bin/bash

usage() {
    cat << USAGE >&2
USAGE:
    $ fairos.sh [COMMAND] [PARAMETERS]
COMMANDS:
    start                       Add FairOS node to the docker network.
    stop                        Stop FairOS node.
PARAMETERS:
    --ephemeral                 Create ephemeral container for the FairOS instance. Data won't be persisted.
    --version=x.y.z             Used version of FairOS client.
    --detach                    It will not log the output of Queen node at the end of the process.
    --hostname=string           Interface to which should the nodes be bound (default 127.0.0.0).
    --stamp=string              Postage Stamp ID for FairOS. If it is omitted, a random postage stamp will be chosen.
    --cookie-domain=string      FairOS login will place session cookies for the given domain. Default is "localhost".
    --cors-origins=string       Comma separated list of URLs to set allowed CORS origins. Default is "*" that allows access from everywhere.
USAGE
    exit 1
}

stop_containers() {
    echo "Stop FairOS container:"
    docker container stop "$FAIROS_CONTAINER_NAME";
}

stop() {
    stop_containers
    trap - SIGINT
    exit 0;
}

container_failure() {
    docker logs "$FAIROS_CONTAINER_NAME";
    stop_containers
    echo "Timeout limit has been reached, exit from the process.."
    exit 1
}

log_container() {
    trap stop SIGINT
    docker logs --tail 25 -f "$FAIROS_CONTAINER_NAME"
}

buy_postage() {
    POSTAGE=$(curl -s -XPOST "http://localhost:1635/stamps/10000/20" | python -c 'import json,sys; obj=json.load(sys.stdin); print(obj["batchID"]);')
    echo "$POSTAGE"
}

MY_PATH=$(dirname "$0")              # relative
MY_PATH=$( cd "$MY_PATH" && pwd )  # absolutized and normalized
# Check used system variable set
FAIROS_VERSION=$("$MY_PATH/utils/env-variable-value.sh" FAIROS_VERSION)
FAIROS_IMAGE_NAME=$("$MY_PATH/utils/env-variable-value.sh" FAIROS_IMAGE_NAME)
BEE_ENV_PREFIX=$("$MY_PATH/utils/env-variable-value.sh" BEE_ENV_PREFIX)
POSTAGE_BUYING_WAITING_TIME=$("$MY_PATH/utils/env-variable-value.sh" POSTAGE_BUYING_WAITING_TIME)

# Init variables
EPHEMERAL=false
LOG=true
FAIROS_CONTAINER_NAME="$BEE_ENV_PREFIX-fairos"
QUEEN_CONTAINER_NAME="$BEE_ENV_PREFIX-queen"
NETWORK="$BEE_ENV_PREFIX-network"
FAIROS_CONTAINER_IN_DOCKER=$(docker container ls -qaf name="$FAIROS_CONTAINER_NAME")
QUEEN_CONTAINER_IN_DOCKER=$(docker container ls -qaf name="$QUEEN_CONTAINER_NAME")
HOSTNAME="127.0.0.1"
CORS_ORIGINS="*"
COOKIE_DOMAIN="localhost"

# Decide script action
case "$1" in
    start)
    shift 1
    ;;
    stop)
    stop
    ;;
    *)
    echoerr "Unknown command: $1"
    usage
    ;;
esac

# Alter variables from flags
while [ $# -gt 0 ]
do
    case "$1" in
        --ephemeral)
        EPHEMERAL=true
        shift 1
        ;;
        --version=*)
        FAIROS_VERSION="${1#*=}"
        shift 1
        ;;
        --detach)
        LOG=false
        shift 1
        ;;
        --hostname=*)
        HOSTNAME="${1#*=}"
        shift 1
        ;;
        --stamp=*)
        STAMP="${1#*=}"
        shift 1
        ;;
        --cors-origins=*)
        CORS_ORIGINS="${1#*=}"
        shift 1
        ;;
        --cookie-domain=*)
        COOKIE_DOMAIN="${1#*=}"
        shift 1
        ;;
        --help)
        usage
        ;;
        *)
        echoerr "Unknown argument: $1"
        usage
        ;;
    esac
done

FAIROS_IMAGE="$FAIROS_IMAGE_NAME:v$FAIROS_VERSION"

if $EPHEMERAL ; then
    EXTRA_DOCKER_PARAMS="--rm"
fi

echo "Starting FairOS instance"

if [ -z "$QUEEN_CONTAINER_IN_DOCKER" ] ; then
    echo "ERROR: Queen Bee node '$QUEEN_CONTAINER_NAME' is not running."
    exit 1
fi

if [ -z "$FAIROS_CONTAINER_IN_DOCKER" ] || $EPHEMERAL ; then
    if [ -z "$STAMP" ] ; then
        echo "Buying stamp on the Queen node..."
        STAMP=$(buy_postage)
        echo "Bought stamp ID: $STAMP"
        echo "Waiting $POSTAGE_BUYING_WAITING_TIME secs until postage stamp is usable..."
        sleep $POSTAGE_BUYING_WAITING_TIME
    fi

    EXTRA_FAIROS_PARAMS="-p $HOSTNAME:9090:9090"
    docker run \
      -d \
      --network="$NETWORK" \
      --name="$FAIROS_CONTAINER_NAME" \
      $EXTRA_DOCKER_PARAMS \
      $EXTRA_FAIROS_PARAMS \
      $FAIROS_IMAGE \
        server \
        --postageBlockId="$STAMP" \
        --cors-origins="$CORS_ORIGINS" \
        --beeApi="http://$QUEEN_CONTAINER_NAME:1633" \
        --beeDebugApi="http://$QUEEN_CONTAINER_NAME:1635" \
        --cookieDomain="$COOKIE_DOMAIN"
else
    docker start "$FAIROS_CONTAINER_IN_DOCKER"
fi

echo "FairOS container has been started"

# log Bee Queen
if $LOG ; then
    log_container
fi
