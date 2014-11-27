default: package

clean:
	rm -rf node_modules
	rm -rf lib

build:
	npm install
	coffee --output lib --compile src

package: clean build
	echo "TODO: package"
	exit 1

publish: package
	echo "TODO: Add publish to npm"
	exit 1

lint:
	echo "TODO: Add lint"
	exit 1

test:
	foreman run --env=test/env node_modules/.bin/mocha -R progress $(TESTARGS)

.PHONY: clean default build package publish lint test
