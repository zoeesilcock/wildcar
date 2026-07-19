cbuffer ShadowUniforms : register(b0, space1)
{
    float4x4 LightViewProjectionModel;
};

struct Input
{
    float3 Position : TEXCOORD0;
};

struct Output
{
    float4 Position : SV_Position;
};

Output main(Input input)
{
  Output output;
  output.Position = mul(LightViewProjectionModel, float4(input.Position, 1.0));
  return output;
}
