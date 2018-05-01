help:
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

start: ## Start dev compilers
	./node_modules/.bin/bsb -make-world -w
.PHONY: start

build: ## Compile app code
	./node_modules/.bin/bsb -make-world
.PHONY: build

clean: ## Wipe compiled assets
	./node_modules/.bin/bsb -clean-world
	rm -fr dist
.PHONY: clean

clean-all: clean ## Wipe all local files
	rm -fr .terraform node_modules
.PHONY: clean-all

tf-plan: .terraform dist/function.zip ## Plan terraform update
	terraform plan
.PHONY: tf-plan

tf-apply: .terraform dist/function.zip ## Apply terraform update
	terraform apply
.PHONY: tf-apply

tf-destroy: .terraform dist/function.zip ## Teardown all infra (!!!)
	terraform destroy
.PHONY: tf-destroy

# TODO: Use webpack or something.
dist/function.zip: build
	mkdir -p dist
	cp src/Main.bs.js dist/main.js
	cd dist && zip -r function.zip main.js

.terraform:
	terraform init
	terraform get
