cbuffer UniformBlock : register(b0, space3)
{
    float4 Color;
    float3 LightDirection;
    float Pad1;
    float3 AmbientColor;
};

struct Input
{
    float3 Normal : TEXCOORD0;
};

float4 main(Input input) : SV_Target0
{
    float brightness = max(0, dot(input.Normal, LightDirection));
    //return float4(input.Normal * 0.5 + 0.5, 1.0); // View normal data as colors.
    float3 finalColor = Color.rgb * (AmbientColor + brightness);
    return float4(finalColor, 1);
}
