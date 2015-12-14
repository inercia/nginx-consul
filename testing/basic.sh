#!/usr/bin/env bash

# simple testing scenario with the help of docker-machine
# - creates 3 VMs with
#    - docker, Weave and Discovery
#    - 1 of them with weave-nginx
#    - 2 of them with a test webserver
# - creates a token
# - all the VMs join the same token

[ -n "$WEAVE_DEBUG" ] && set -x

CHECK=
STOP=
NGINX_MACHINES="gateway"
WEBSERVER_MACHINES="host1 host2"
ALL_MACHINES="$NGINX_MACHINES $WEBSERVER_MACHINES"
ALL_MACHINE_COUNT=$(echo $ALL_MACHINES | wc -w)

DISCO_TOKEN_URL=https://discovery-stage.hub.docker.com/v1/clusters
DISCO_SCRIPT_URL=https://raw.githubusercontent.com/weaveworks/discovery/master/discovery

WEAVE_SCRIPT=$GOPATH/src/github.com/weaveworks/weave/weave
NGINX_IMAGE="inercia/weave-nginx"
NGINX_IMAGE_FILES="../docker_nginx_consul.tar"
ALL_IMAGE_FILES="$NGINX_IMAGE_FILES \
                 $GOPATH/src/github.com/weaveworks/weave/weave.tar \
                 $GOPATH/src/github.com/weaveworks/discovery/weavediscovery.tar"
REMOTE_ROOT=/home/docker
WEAVE=$REMOTE_ROOT/weave
WEAVER_PORT=6783
TOKEN=

SERVICE=webserver
EXT_PORT=80
INT_PORT=8080

log() { echo ">>> $1" >&2 ; }

############################
# main
############################

while [ $# -gt 0 ] ; do
    case "$1" in
        -check|--check)
            CHECK=1
            ;;
        --token)
            TOKEN="$2"
            shift
            ;;
        --token=*)
            TOKEN="${1#*=}"
            ;;
        --stop)
            STOP=1
            ;;
        *)
            break
            ;;
    esac
    shift
done

# Get a token
[ -z "$TOKEN" ] && TOKEN=$(curl --silent -X POST $DISCO_TOKEN_URL)

# Create two machines
for machine in $ALL_MACHINES ; do
    STATUS=$(docker-machine status $machine 2>&1)
    if [ $? -ne 0 ] ; then
        log "Creating $machine (VirtualBox)..."
        docker-machine create --driver virtualbox $machine
    elif [ "$STATUS" = "Stopped" ] ; then
        log "Starting $machine..."
        docker-machine start $machine
    fi
done

log "Building..."
make -C ..

log "Uploading images"
for machine in $ALL_MACHINES ; do
    log "... uploading Weave script to $machine"
    docker-machine scp $WEAVE_SCRIPT $machine:$REMOTE_ROOT/ >/dev/null
    
    for image in $ALL_IMAGE_FILES ; do
        log "... uploading $image to $machine"
        docker-machine scp $image $machine:$REMOTE_ROOT/image-$(basename $image) >/dev/null
    done
done

for machine in $ALL_MACHINES ; do
    advertise=$(docker-machine ip $machine):$WEAVER_PORT

    SCRIPT=$(tempfile)
    cat <<-EOF > $SCRIPT
#!/bin/sh

        for C in weave weaveproxy webserver nginx weavediscovery ; do
            echo ">>> Stopping \$C"
            docker stop \$C  >/dev/null 2>&1 || /bin/true
            docker rm \$C    >/dev/null 2>&1 || /bin/true
        done

        for image in $REMOTE_ROOT/image-*.tar ; do
            echo ">>> Loading image \$image"
            docker load -i \$image
        done

        echo ">>> Installing and launching Weave"
        cd $REMOTE_ROOT                         && \
            sudo chmod a+x $WEAVE               && \
            $WEAVE launch --init-peer-count $ALL_MACHINE_COUNT --log-level=debug

        sleep 3

        echo ">>> Installing and launching Discovery (advertising $advertise)"
        cd $REMOTE_ROOT                              && \
            curl --silent -L -O $DISCO_SCRIPT_URL    && \
            chmod a+x $REMOTE_ROOT/discovery         && \
            $REMOTE_ROOT/discovery join --advertise=$advertise token://$TOKEN

        if [ "\$1" = "webserver" ] ; then
            echo ">>> Launching webserver"
            $WEAVE run -p $INT_PORT:$INT_PORT -ti --name $SERVICE adejonge/helloworld &
        else
            echo ">>> Launching weave/nginx"
            $WEAVE run -p $EXT_PORT:$EXT_PORT --name nginx $NGINX_IMAGE $EXT_PORT:$SERVICE:$INT_PORT   &
        fi
EOF
    
    log "Preparing provisioning for $machine..."
    docker-machine scp $SCRIPT $machine:$REMOTE_ROOT/provision.sh >/dev/null
    rm -f $SCRIPT
done

for machine in $NGINX_MACHINES ; do
    log "Provisioning $machine (gateway)..."
    docker-machine ssh $machine sh $REMOTE_ROOT/provision.sh nginx     &
done
for machine in $WEBSERVER_MACHINES ; do
    log "Provisioning $machine (webserver)..."
    docker-machine ssh $machine sh $REMOTE_ROOT/provision.sh webserver &
done

GATEWAY_IP=$(docker-machine ip gateway)
echo "Wait a few seconds until everything is up and then launch one of these:"
echo "$ curl http://$GATEWAY_IP:$EXT_PORT/"
echo "$ ab -k -c 350 -n 20000 http://$GATEWAY_IP:$EXT_PORT/"

