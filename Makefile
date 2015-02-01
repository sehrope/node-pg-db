default: package

clean:
	rm -rf node_modules
	rm -rf lib
	rm -rf lib-cov
	rm -rf cov

compile:
	node_modules/.bin/coffee --bare --output lib --compile src

build:
	npm install
	node_modules/.bin/coffee --bare --output lib --compile src

package: clean build

publish: test lint package
	npm publish

lint:
	node_modules/.bin/coffeelint src test

test: compile
	foreman run --env=test/env node_modules/.bin/mocha --reporter tap $(TESTARGS)

compile-cov:
	rm -rf lib-cov
	node_modules/.bin/coffeeCoverage --initfile lib-cov/init.js --bare src lib-cov

test-cov: compile-cov
	rm -rf cov/coffee.html
	mkdir -p cov
	COVERAGE=true foreman run --env=test/env node_modules/.bin/mocha --reporter html-cov --require ./lib-cov/init.js $(TESTARGS) > cov/coffee.html
	node_modules/.bin/opn cov/coffee.html

compile-cov-js: compile
	rm -rf lib-cov
	node_modules/.bin/jscoverage lib lib-cov

test-cov-js: compile-cov-js
	rm -rf cov/js.html
	mkdir -p cov
	COVERAGE=true foreman run --env=test/env node_modules/.bin/mocha --reporter html-cov  $(TESTARGS) > cov/js.html
	node_modules/.bin/opn cov/js.html

.PHONY: clean default build package publish lint test compile-cov test-cov compile-cov-js test-cov-js
