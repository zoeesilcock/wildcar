cbuffer UniformBlock : register(b0, space3)
{
    float4 Color;
};

struct Input
{
    float3 Normal : TEXCOORD0;
    float3 WorldPosition : TEXCOORD1;
};

float4 main(Input input) : SV_Target0
{
    return Color;
}
