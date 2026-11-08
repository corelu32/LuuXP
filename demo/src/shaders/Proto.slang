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

    float2 positions[3] = {
        float2( 0.0, -0.5),  // Top
        float2( 0.5,  0.5),  // Bottom Right
        float2(-0.5,  0.5)   // Bottom Left
    };

    float3 colors[3] = {
        float3(1.0, 0.0, 0.0), // Red
        float3(0.0, 1.0, 0.0), // Green
        float3(0.0, 0.0, 1.0)  // Blue
    };

    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.color    = float4(colors[vertexID], 1.0);

    return output;
}

// Struct to explicitly match Vulkan Color Target Binding 0
struct FragmentStageOutput
{
    float4 color : SV_Target0; 
};

// --- FRAGMENT SHADER ENTRY POINT ---
[shader("fragment")]
FragmentStageOutput FragmentMain(VertexStageOutput input) // Return the structure
{
    FragmentStageOutput output;
    output.color = input.color;
    return output;
}