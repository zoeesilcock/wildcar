cbuffer UniformBlock : register(b0, space3)
{
    float4 Color;
};

float4 main() : SV_Target0
{
    return Color;
}
