pub const native = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
    @cInclude("SDL3_mixer/SDL_mixer.h");
    @cInclude("physfs.h");
    @cInclude("spirv_reflect.h");
});