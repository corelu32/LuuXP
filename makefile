all:
	@echo "Usage:"
	@echo "  make run-demo"

run-demo:
	@zig build --build-file ./demo/build.zig run -freference-trace=16