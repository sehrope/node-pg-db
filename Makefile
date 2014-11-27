default: package

clean:
	rm -rf node_modules
	rm -rf lib

build:
	coffee --output lib --compile src

package: clean build
	echo "TODO: package"

publish: package
	echo "TODO: Add publish to npm"

lint:
	grunt lint

test:
	foreman run --env=test/env node_modules/.bin/mocha -R progress $(TESTARGS)

.PHONY: clean default build package publish lint test
