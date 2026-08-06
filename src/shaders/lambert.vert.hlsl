cbuffer UniformBlock : register(b0, space1)
{
    float4x4 Transform;
    float4x4 Model;
};

struct Input
{
    float3 Position : TEXCOORD0;
    float3 Normal : TEXCOORD1;
    float2 UV : TEXCOORD2;
};

struct Output
{
    float3 Normal : TEXCOORD0;
    float3 WorldPosition : TEXCOORD1;
    float2 UV : TEXCOORD2;
    float4 Position : SV_Position;
};

Output main(Input input)
{
    Output output;
    float4 worldPosition = mul(Model, float4(input.Position, 1.0));

    output.Normal = normalize(mul((float3x3)Model, input.Normal));
    output.WorldPosition = worldPosition.xyz;
    output.UV = input.UV;
    output.Position = mul(Transform, float4(input.Position, 1.0));
    return output;
}
