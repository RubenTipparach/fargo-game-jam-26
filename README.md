# Fargo Game Jam 26 - Dark Nebula

A 3D space game built with Picotron featuring lit rendering, textured planets, and dynamic lighting.

## Features

- **3D Rendering Engine**: Custom 3D renderer with camera controls
- **Lit Shader System**: 8-level brightness system using color table remapping
- **Textured Planet**: UV-mapped sphere with rotating texture
- **Dynamic Lighting**: Directional lighting with WASD controls
- **Batch Star Rendering**: Efficient rendering of 500+ stars
- **Mouse Orbit Camera**: Intuitive camera controls

## Project Structure

```
dark-neb.p64/
├── main.lua              # Main game loop and initialization
├── config.lua            # Game configuration (camera, lighting, objects)
├── src/
│   ├── lighting.lua      # Lighting utilities
│   ├── engine/
│   │   ├── renderer.lua      # Non-lit 3D renderer
│   │   ├── renderer_lit.lua  # Lit 3D renderer with brightness caching
│   │   ├── render_flat.lua   # Flat shading renderer
│   │   └── obj_loader.lua    # OBJ file loader
│   └── 0.pal             # Color palette
└── shippy1.obj           # Ship 3D model
```

## Controls

- **Mouse (Left Click + Drag)**: Orbit camera around scene
- **W/A/S/D or Arrow Keys**: Rotate light direction
- **Debug Mode**: Set `Config.debug = true` in config.lua

## Technical Details

### Rendering System

The project uses a dual-renderer architecture:
- `Renderer`: Non-lit renderer for basic 3D rendering
- `RendererLit`: Advanced renderer with 8-level brightness system using sprite color table remapping

### Brightness Caching

The lit renderer uses a sprite caching system:
- Sprites 128-255 are used for cached brightness variants
- Each sprite can have 8 brightness levels (0=darkest, 7=brightest)
- Color remapping is done via color table (sprite 16)

### Configuration

All game parameters are centralized in `config.lua`:
- Star count and colors
- Camera distance and sensitivity
- Ship/Planet position and rotation
- Lighting parameters (yaw, pitch, brightness, ambient)
- Rendering settings (render distance, clear color)

## Development

Built for Picotron 0.2.1c using Lua.

### Performance

- 500 stars rendered individually with projection
- Planet uses UV-mapped sphere mesh
- Ship uses loaded OBJ model
- CPU usage typically <80% at 30fps
