include docker.mk

BEHAT ?= "vendor/bin/behat"
SITE ?= "default"
PROFILE ?= "minimal"
ENVIRONMENT ?= "stg"


## info	:	Show project info
.PHONY: info
info:
	@scripts/get_info.sh

## test	:	Run Unit tests. Pass the path to a file or directory with the Unit test. Example: make test web/modules/contrib/devel/tests/src/Unit
.PHONY: test
test:
	docker-compose exec php phpunit $(filter-out $@,$(MAKECMDGOALS))

## behat	:	Run project Behat tests
.PHONY: behat
behat:
	docker-compose exec php  ${BEHAT} --colors

## ngrok	:	Setup a ngrok tunnel to make the site available
.PHONY: ngrok
ngrok:
	docker-compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.ngrok.yml up -d && docker-compose exec php curl http://ngrok:4040/api/tunnels | grep -Po "https"://[^\"]+

## ngrok-stop	:	Stop the created ngrok tunnel
.PHONY: ngrok-stop
ngrok-stop:
	docker-compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.ngrok.yml stop ngrok && docker-compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.ngrok.yml rm -fsv ngrok

## frontend	:	Generate frontend assets like compiling scss
.PHONY: frontend
frontend:
	docker-compose exec node sh ${DOCKER_PROJECT_ROOT}/scripts/frontend-build.sh $(filter-out $@,$(MAKECMDGOALS))

## backstopjs-reference	:	Generate BackstopJS reference files
.PHONY: backstopjs-reference
backstopjs-reference:
	docker-compose exec backstopjs backstop reference

## backstopjs-test	:	Run BackstopJS tests
.PHONY: backstopjs-test
backstopjs-test:
	docker-compose exec backstopjs backstop test

## init-setup	:	Prepares the site
.PHONY: init-setup
init-setup:
	mkdir -p web/sites/default/files/behat/errors
	chmod u+w web/sites/${SITE} -R
	cp docker-compose.override.yml.dist docker-compose.override.yml
	cp web/sites/${SITE}/example.settings.local.php web/sites/${SITE}/settings.local.php
	cp web/sites/${SITE}/example.local.drush.yml web/sites/${SITE}/local.drush.yml
	docker-compose up -d
	docker-compose exec -T php composer install
	docker-compose run -e'PHP_ERROR_REPORTING=E_ALL & ~E_DEPRECATED' --rm -T php 'vendor/bin/grumphp' 'git:init'

## setup	:	Prepares the site and installs it using the Drupal configuration files
.PHONY: setup
setup:
	make init-setup
	docker-compose exec -T php drush @${SITE}.local si ${PROFILE} --existing-config --sites-subdir=${SITE} -y
	docker-compose exec -T php drush @${SITE}.local cim -y
	docker-compose exec -T php drush @${SITE}.local cr
	docker-compose exec -T php drush @${SITE}.local uli

## setup-from-environment	:	Prepares the site and loads it with data from the reference site
.PHONY: setup-from-environment
setup-from-environment:
	make init-setup
	./scripts/reload-local.sh --site=${SITE} --env=${ENVIRONMENT}

## solr-sync	:	Reload docker Solr cores from local files.
.PHONY: solr-sync
solr-sync:
	./scripts/solr-sync.sh ${PROJECT_NAME} ${SOLR_CONTAINER} ${CORES}

## solr-rebuild	:	Re-creates the Solr core
.PHONY: solr-rebuild
solr-rebuild:
	docker-compose stop solr && docker-compose rm -f solr && docker-compose up -d solr && make solr-sync
