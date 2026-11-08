# If the first argument is "run-demo"...
ifeq ($(firstword $(MAKECMDGOALS)),run-demo)
  # Capture everything after "run-demo" as arguments
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # Turn those trailing words into do-nothing targets so make doesn't complain
  $(eval $(RUN_ARGS):;@:)
endif

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

all:
	@echo "Usage:"
	@echo "  make run-demo [args]"
	@echo "  make build-demo-shaders"

run-demo:
	@zig build --build-file ./demo/build.zig run -freference-trace=16 -- $(RUN_ARGS)

build-demo-shaders:
	@slangc $(ROOT)/demo/src/shaders/Demo.slang -target spirv -entry VertexMain   -stage vertex   -o $(ROOT)/demo/.assets/Demo.vert.spv
	@slangc $(ROOT)/demo/src/shaders/Demo.slang -target spirv -entry FragmentMain -stage fragment -o $(ROOT)/demo/.assets/Demo.frag.spv