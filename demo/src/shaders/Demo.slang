struct Items {
    int nums[10];
    matrix<int, 2, 3> data;
    vector<float, 3> particle1;
    vector<float, 3> particle2;
    vector<float, 3> particle3;
    vector<float, 3> particleExtras;
}

cbuffer Uniforms
{
    float U_Time;
    float U_Aspect;
    float U_Fov;
    float U_Near;
    float U_Far;
}

cbuffer UniformsDummyA
{
    float U_UNUSED_X;
    Items U_UNUSED_items;
}

cbuffer UniformsDummyB
{
    float U_UNUSED_Y;
    float U_UNUSED_Z;
}

float4 CalculatePerspective(float3 coord)
{
    float4 clip_pos;

    clip_pos.x = coord.x * U_Fov / U_Aspect;
    clip_pos.y = coord.y * U_Fov;
    clip_pos.z = U_Far / (U_Far - U_Near) * coord.z - U_Far * U_Near / (U_Far - U_Near);
    clip_pos.w = coord.z;

    return clip_pos;
}

struct VertexResult
{
    float4 Position : SV_Position;
    float4 Color;
};

[shader("vertex")]
VertexResult VertexMain(uint vertexID : SV_VertexID, uint objectID : SV_InstanceID)
{
    VertexResult result;
    
    float2 positions[3] = {
        float2( 0.0f,  0.5f),
        float2( 0.5f, -0.5f),
        float2(-0.5f, -0.5f)
    };
    
    float4 colors[3] = {
        float4(1.0f, 0.0f, 0.0f, 0.5f),
        float4(0.0f, 1.0f, 0.0f, 0.5f),
        float4(0.0f, 0.0f, 1.0f, 0.5f)
    };

    float3 raw_pos;

    raw_pos.x = positions[vertexID].x + sin(U_Time + objectID * 0.2 + 0.1f) * 0.8f + 0.2 + sin(U_Time) + 0.341;
    raw_pos.y = positions[vertexID].y + cos(U_Time + objectID * 0.15 + 0.1f) * 0.3f;
    raw_pos.z = 2.0f + sin(U_Time + objectID * 0.1) * 0.6f;

    // Force dummy uniforms to exist (for testing purposes!!!)
    raw_pos.x += (U_UNUSED_X + U_UNUSED_Y + U_UNUSED_Z) * 0.00001;
    raw_pos.x += U_UNUSED_items.data._m00;

    result.Position = CalculatePerspective(raw_pos);
    result.Color = colors[vertexID] - (sin(U_Time + objectID * 0.3) * 0.6f) * 0.01f + 0.5f;

    return result;
}

[shader("fragment")]
float4 FragmentMain(VertexResult input) : SV_Target0
{
    return input.Color;
}