PUBLISH=publish_docker_nginx_consul

.DEFAULT: all
.PHONY: all update tests publish $(PUBLISH) clean prerequisites build

# If you can use docker without being root, you can do "make SUDO="
SUDO=sudo

DOCKERHUB_USER=inercia
DOCKER_NGINX_CONSUL_VERSION=git-$(shell git rev-parse --short=12 HEAD)

DOCKER_NGINX_CONSUL_UPTODATE=.docker_nginx_consul.uptodate
IMAGES_UPTODATE=$(DOCKER_NGINX_CONSUL_UPTODATE)
DOCKER_NGINX_CONSUL_IMAGE=$(DOCKERHUB_USER)/docker-nginx-consul
IMAGES=$(DOCKER_NGINX_CONSUL_IMAGE)
DOCKER_NGINX_CONSUL_EXPORT=docker_nginx_consul.tar

all:    $(DOCKER_NGINX_CONSUL_UPTODATE)
dist:   $(DOCKER_NGINX_CONSUL_EXPORT)

$(DOCKER_NGINX_CONSUL_UPTODATE): Dockerfile nginx.conf service.template wrapper.sh lua/consul.lua
	$(SUDO) docker build -t $(DOCKER_NGINX_CONSUL_IMAGE) .
	touch $@

$(DOCKER_NGINX_CONSUL_EXPORT): $(IMAGES_UPTODATE)
	$(SUDO) docker save $(addsuffix :latest,$(IMAGES)) > $@

$(DOCKER_DISTRIB):
	curl -o $(DOCKER_DISTRIB) $(DOCKER_DISTRIB_URL)

$(PUBLISH): publish_%:
	$(SUDO) docker tag -f $(DOCKERHUB_USER)/$* $(DOCKERHUB_USER)/$*:$(DOCKER_NGINX_CONSUL_VERSION)
	$(SUDO) docker push   $(DOCKERHUB_USER)/$*:$(DOCKER_NGINX_CONSUL_VERSION)
	$(SUDO) docker push   $(DOCKERHUB_USER)/$*:latest

publish: $(PUBLISH)

clean:
	-$(SUDO) docker rmi $(IMAGES) 2>/dev/null
	rm -f $(EXES) $(IMAGES_UPTODATE) $(DOCKER_NGINX_CONSUL_EXPORT) test/tls/*.pem coverage.html profile.cov

