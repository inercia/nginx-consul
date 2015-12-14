#!/bin/bash


CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAME="docker-nginx-consul"
NGINX=/usr/local/openresty/nginx/sbin/nginx

# the service template and wehere it will be written to
NGINX_SERVICE_TEMPLATE=${NGINX_SERVICE_TEMPLATE:-$CURR_DIR/service.template}
NGINX_SERVICES_DIR=${NGINX_SERVICES_DIR:-/usr/local/openresty/nginx/conf/sites-enabled}

# where our Lua scripts are
LUA_LIBRARY=${LUA_LIBRARY:-$CURR_DIR/lua}

#########################################

usage() {
    cat <<-EOF
    
Usage:

    $NAME <CONSUL> <SERVICE> [<SERVICE> ...]

where <CONSUL>  = <CONSUL_HOST>:<CONSUL_PORT>
      <SERVICE> = <EXT_PORT>:<NAME>

Example:

   $NAME 127.0.0.1:8500 80:webserver

EOF
}

log()             { echo "$1" >&2 ;            }
fatal()           { log "FATAL: $1" ; exit 1 ; }
usage_fatal()     { log "ERROR: $1" ; usage  ; exit 1 ; }
replace()         { sed -e "s|@@$1@@|$2|g" ; }

VALID_HOSTNAME_RE="^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])$"
VALID_IP_RE="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
VALID_PORT_NUM_RE="^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"

parse_addr()        { echo $1 | cut -d':' -f1    ; }
parse_port()        { echo $1 | cut -d':' -f2 -s ; }

valid_ip()                   { echo $1 | grep -E -q $VALID_IP_RE ;       }
valid_hostname()             { echo $1 | grep -E -q $VALID_HOSTNAME_RE ; }
valid_addr()                 { valid_hostname $1 || valid_ip $1 ;        }
valid_port_num()             { echo $1 | grep -E -q $VALID_PORT_NUM_RE ; }
valid_addr_and_port()        { valid_addr $(parse_addr $1) && valid_port_num $(parse_port $1) ; }

#########################################
# main
#########################################

CONSUL=$1
valid_addr_and_port $CONSUL || usage_fatal "no valid Consul address provided"
CONSUL_ADDR=$(parse_addr $CONSUL)
CONSUL_PORT=$(parse_port $CONSUL)
shift

[ $# -ge 1 ] || usage_fatal "no service(s) provided"
while [ $# -gt 0 ]; do
    MAPPING=$1
    [ -n "$MAPPING" ] || usage_fatal "no mapping provided"

    EXT_PORT=$(echo $MAPPING | cut -d':' -f1)
    valid_port_num $EXT_PORT || usage_fatal "\"$EXT_PORT\" does not seem a valid port number"
    NAME=$(echo $MAPPING | cut -d':' -f2)

    [ -n "$EXT_PORT" ]   || usage_fatal "no external port provided in mapping"
    [ -n "$NAME"     ]   || usage_fatal "no name provided in mapping"

    SERVICE_FILE=$NGINX_SERVICES_DIR/$NAME-$EXT_PORT-$INT_PORT

    log "Adding service $EXT_PORT -> $NAME:$INT_PORT"
    [ -d $NGINX_SERVICES_DIR ] || mkdir -p $NGINX_SERVICES_DIR
    cat $NGINX_SERVICE_TEMPLATE | \
        replace "NAME"        "$NAME"             | \
        replace "CONSUL_ADDR" "$CONSUL_ADDR"      | \
        replace "CONSUL_PORT" "$CONSUL_PORT"      | \
        replace "EXT_PORT"    "$EXT_PORT"         | \
        replace "LUA_LIBRARY" "$LUA_LIBRARY" > $SERVICE_FILE \
            || fatal "could not write file"

    shift
done

log "Starting nginx (with consul://$CONSUL_ADDR:$CONSUL_PORT/)"
$NGINX -g 'daemon off;'
