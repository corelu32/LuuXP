# If the first command-line word matches either target...
ifeq ($(firstword $(MAKECMDGOALS)),$(filter $(firstword $(MAKECMDGOALS)),run-demo build-demo-shaders))
  # Capture everything after the target name
  TRAILING_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # Turn those trailing words into do-nothing targets so make doesn't complain
  $(eval $(TRAILING_ARGS):;@:)
endif

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Default shader name if none is provided
SHADER_NAME := $(if $(firstword $(TRAILING_ARGS)),$(firstword $(TRAILING_ARGS)),Demo)

all:
	@echo "Usage:"
	@echo "  make run-demo [args]"
	@echo "  make build-demo-shaders [ShaderName]"

run-demo:
	@zig build --build-file ./demo/build.zig run -freference-trace=16 -- $(TRAILING_ARGS)

build-demo-shaders:
	@slangc $(ROOT)/demo/src/shaders/$(SHADER_NAME).slang -target spirv -entry VertexMain   -stage vertex   -o $(ROOT)/demo/.assets/$(SHADER_NAME).vert.spv
	@slangc $(ROOT)/demo/src/shaders/$(SHADER_NAME).slang -target spirv -entry FragmentMain -stage fragment -o $(ROOT)/demo/.assets/$(SHADER_NAME).frag.spv