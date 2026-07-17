cbuffer UniformBlock : register(b0, space3)
{
    float4 Color;
    float3 LightDirection;
};

struct Input
{
    float3 Normal : TEXCOORD0;
};

float4 main(Input input) : SV_Target0
{
    float brightness = max(0, dot(input.Normal, LightDirection));
    //return float4(input.Normal * 0.5 + 0.5, 1.0); // View normal data as colors.
    return Color * brightness;
}
