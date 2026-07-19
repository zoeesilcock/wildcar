cbuffer UniformBlock : register(b0, space3)
{
    float4 Color;
};

Texture2D<float> ShadowMap : register(t0, space2);
SamplerState ShadowSampler : register(s0, space2);

cbuffer LightingBlock : register(b1, space3)
{
    float4x4 LightViewProjection;
    float3 LightDirection;
    float Pad1;
    float3 LightColor;
    float Pad2;
    float3 AmbientColor;
};

struct Input
{
    float3 Normal : TEXCOORD0;
    float3 WorldPosition : TEXCOORD1;
};

float4 main(Input input) : SV_Target0
{
    float4 lightClip = mul(LightViewProjection, float4(input.WorldPosition, 1.0));
    float3 lightNDC = lightClip.xyz / lightClip.w;

    float2 shadowUV = lightNDC.xy * 0.5 + 0.5;
    shadowUV.y = 1.0 - shadowUV.y;
    float fragmentDepth = lightNDC.z;

    float visibility = 1.0;
    bool insideShadowMap =
        shadowUV.x >= 0.0 && shadowUV.x <= 1.0 &&
        shadowUV.y >= 0.0 && shadowUV.y <= 1.0 &&
        fragmentDepth >= 0.0 && fragmentDepth <= 1.0;

    if (insideShadowMap) {
        float shadowBias = 0.001;
        float storedDepth = ShadowMap.Sample(ShadowSampler, shadowUV);
        visibility = fragmentDepth >= storedDepth - shadowBias ? 1.0 : 0.0;
    }

    float brightness = max(0, dot(input.Normal, LightDirection));

    //return float4(input.Normal * 0.5 + 0.5, 1.0); // View normal data as colors.
    //return float4(shadowUV, fragmentDepth, 1.0); // View distance from main light.

    float3 finalColor = Color.rgb * (AmbientColor + LightColor * brightness * visibility);
    return float4(finalColor, 1.0);
}
