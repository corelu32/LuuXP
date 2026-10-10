ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

all:
	@echo "Usage:"
	@echo "  make run-demo"
	@echo "  make build-demo-shaders"

run-demo:
	@zig build --build-file ./demo/build.zig run -freference-trace=16

build-demo-shaders:
	@slangc $(ROOT)/demo/src/shaders/Demo.slang -target spirv -entry VertexMain   -stage vertex   -o $(ROOT)/demo/.assets/Demo.vert.spv
	@slangc $(ROOT)/demo/src/shaders/Demo.slang -target spirv -entry FragmentMain -stage fragment -o $(ROOT)/demo/.assets/Demo.frag.spv