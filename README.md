Reverse-proxy/load-balancer for Docker networks with Consul
===========================================================

Dynamic reverse proxy and load balancer for microservices running in a Docker network,
based on [nginx](http://nginx.org) and Consul.

Scenario
--------

You have `n` webservers running in `host1`..`hostn` in containers.
You want to have a reverse proxy running in `gateway` that load balances requests
to all these `webserver` containers. 

Design
======

The load-balancer is based on a Lua script that runs in the _nginx_ process and
_watches_ a service in a Consul server. As long as your Consul server has
up-to-date information about your containers, any container that appears with
that name will be immediately available as an upstream server in _nginx_,
and containers being stopped or dying will be immediately removed from this pool.

Usage
=====

Running Consul
--------------

I will no try to explain how to use Consul, but as a quick-start method,
you could run it with:

```Bash
    $ docker run -p 8400:8400 -p 8500:8500 -p 8600:53/udp -h node1 progrium/consul -server -bootstrap -ui-dir /ui
```

Then you could check the DNS interface is usable with:

```Bash
    $ dig @localhost -p 8600 node1.node.consul

    ; <<>> DiG 9.9.5-11ubuntu1-Ubuntu <<>> @localhost -p 8600 node1.node.consul
    ; (1 server found)
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 13474
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

    ;; QUESTION SECTION:
    ;node1.node.consul.		IN	A

    ;; ANSWER SECTION:
    node1.node.consul.	0	IN	A	172.17.0.2

    ;; Query time: 0 msec
    ;; SERVER: 127.0.0.1#8600(127.0.0.1)
    ;; WHEN: Mon Dec 14 13:02:33 CET 2015
    ;; MSG SIZE  rcvd: 68
```

the API with

```Bash
    $ curl localhost:8500/v1/catalog/nodes
    [{"Node":"node1","Address":"172.17.0.2"}]
```

and the Web UI at [http://127.0.0.1:8500/ui](http://127.0.0.1:8500/ui)

With Weave
----------

- Launch Weave in your `host*` machines as you usually do
([docs](http://docs.weave.works/weave/latest_release/))
(we will use the [proxy](http://docs.weave.works/weave/latest_release/proxy.html) 
in this example):

```Bash
    host1$ weave launch --init-peer-count n
    host1$ eval $(weave env)
```

- Connect all these these peers in some way (with `weave connect`,
with [Weave Discovery](https://github.com/weaveworks/discovery), etc)
- Launch your `webserver`s. In this example, we use a minimal `webserver`
that listens on port 8080:

```Bash
    host1$ docker run -p 8080:8080 --rm  -ti --name webserver  adejonge/helloworld
```

Launch as many webservers as you want, but all registered with the
*same hostname* (`webserver`) and listening on the *same port*.

- On the gateway host, also launch Weave and the reverse proxy.

```Bash
    gateway$ weave launch
    gateway$ eval $(weave env)
    gateway$ docker run -p 80:80 inercia/docker-nginx-consul localhost:8500 80:webserver
```

You could expose and load-balance more services by adding them to the
command line. For example:

```Bash
    gateway$ docker run -p 80:80 -p 81:81 inercia/docker-nginx-consul localhost:8500 80:webserver 81:graphite
```

- Open port 80 on the gateway and let you user request come in!

TODO
====



