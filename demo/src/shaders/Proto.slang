// Structural layout for passing data from the Vertex to Fragment shader
struct VertexStageOutput
{
    float4 position : SV_Position;
    float4 color    : COLOR;
};

// --- VERTEX SHADER ENTRY POINT ---
[shader("vertex")]
VertexStageOutput VertexMain(uint vertexID : SV_VertexID)
{
    VertexStageOutput output;

    // Hardcoded screen coordinates for 3 triangle vertices (Clockwise layout)
    float2 positions[3] = {
        float2( 0.0, -0.5),  // Top
        float2( 0.5,  0.5),  // Bottom Right
        float2(-0.5,  0.5)   // Bottom Left
    };

    // Hardcoded RGB colors for each vertex
    float3 colors[3] = {
        float3(1.0, 0.0, 0.0), // Red
        float3(0.0, 1.0, 0.0), // Green
        float3(0.0, 0.0, 1.0)  // Blue
    };

    // Assign vertex data based on the built-in system Vertex ID
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.color    = float4(colors[vertexID], 1.0);

    return output;
}

// --- FRAGMENT SHADER ENTRY POINT ---
[shader("fragment")]
float4 FragmentMain(VertexStageOutput input) : SV_Target
{
    // Return the automatically interpolated vertex color
    return input.color;
}
