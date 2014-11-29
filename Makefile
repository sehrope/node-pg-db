default: package

clean:
	rm -rf node_modules
	rm -rf lib
	rm -rf lib-cov
	rm -rf cov

compile:
	coffee --bare --output lib --compile src

build:
	npm install
	coffee --bare --output lib --compile src

package: clean build

publish: package
	echo "TODO: Add publish to npm"
	exit 1

lint:
	echo "TODO: Add lint"
	exit 1

test: compile
	foreman run --env=test/env node_modules/.bin/mocha --reporter tap $(TESTARGS)

compile-cov:
	rm -rf lib-cov
	node_modules/.bin/coffeeCoverage --initfile lib-cov/init.js --bare src lib-cov

test-cov: compile-cov
	rm -rf cov
	mkdir -p cov
	COVERAGE=true foreman run --env=test/env node_modules/.bin/mocha --reporter html-cov --require ./lib-cov/init.js $(TESTARGS) > cov/index.html
	open cov/index.html

compile-cov-js: compile
	rm -rf lib-cov
	node_modules/.bin/jscoverage lib lib-cov

test-cov-js: compile-cov-js
	rm -rf cov
	mkdir -p cov
	COVERAGE=true foreman run --env=test/env node_modules/.bin/mocha --reporter html-cov  $(TESTARGS) > cov/index.html
	open cov/index.html

.PHONY: clean default build package publish lint test compile-cov test-cov compile-cov-js test-cov-js
