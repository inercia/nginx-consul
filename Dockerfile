FROM debian:jessie

# install nginx+openresty
RUN apt-get update && \
    apt-get install -y ca-certificates     \
                       libreadline-dev     \
                       libncurses5-dev     \
                       libpcre3-dev        \
                       libssl-dev          \
                       wget                \
                       dnsutils            \
                       perl                \
                       unzip               \
                       make                \
                       build-essential  && \
    cd /tmp                             && \
    wget https://openresty.org/download/ngx_openresty-1.9.3.1.tar.gz && \
    tar xzvf ngx_openresty-*.tar.gz     && \
    cd ngx_openresty-*                  && \
    ./configure                         && \
    make                                && \
    make install                        && \
    rm -rf ngx_openresty-*              && \
    apt-get remove -y libreadline-dev      \
                      libncurses5-dev      \
                      libpcre3-dev         \
                      libssl-dev           \
                      perl                 \
                      make                 \
                      build-essential   && \
    apt-get autoremove -y               && \
    apt-get clean                       && \
    apt-get purge                       && \
    rm -rf /var/lib/apt/lists/*

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log && \
    ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log

RUN     mkdir -p /home/nginx/lua/resty

# install HTTP-Resty package
RUN     cd /tmp                                                                  && \
        wget https://github.com/pintsized/lua-resty-http/archive/master.zip      && \
        unzip -xU master.zip                                                     && \
        mv lua-resty-http-master/lib/resty/* /home/nginx/lua/resty/            && \
        rm -rf lua-resty-http-master master.zip

# install Consul-Resty package
RUN     cd /tmp                                                                  && \
        wget https://github.com/hamishforbes/lua-resty-consul/archive/master.zip && \
        unzip -xU master.zip                                                     && \
        mv lua-resty-consul-master/lib/resty/* /home/nginx/lua/resty/            && \
        rm -rf lua-resty-consul-master master.zip

ADD nginx.conf                    /usr/local/openresty/nginx/conf/
ADD wrapper.sh service.template   /home/nginx/
ADD lua                           /home/nginx/lua

VOLUME ["/var/cache/nginx"]

ENTRYPOINT ["/home/nginx/wrapper.sh"]

