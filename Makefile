build:
	@cabal build

configure:
	@cabal configure -f eclair-debug --enable-tests

clean:
	@cabal clean

run:
	@cabal run

test:
	@cabal run eclair-test --flag eclair-lang:-debug

repl:
	@cabal repl

.PHONY: build configure clean run test repl
