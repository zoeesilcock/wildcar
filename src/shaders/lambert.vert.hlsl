cbuffer UniformBlock : register(b0, space1)
{
    float4x4 Transform : packoffset(c0);
};

struct Input
{
    float3 Position : TEXCOORD0;
    float3 Normal : TEXCOORD1;
};

struct Output
{
    float3 Normal : TEXCOORD0;
    float4 Position : SV_Position;
};

Output main(Input input)
{
    Output output;
    output.Normal = input.Normal;
    output.Position = mul(Transform, float4(input.Position, 1.0f));
    return output;
}
