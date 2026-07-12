cbuffer SkyColors : register(b0, space3)
{
    float4 horizon_color;
    float4 zenith_color;
};

struct Input
{
    float3 view_ray : TEXCOORD0;
};

float4 main(Input input) : SV_Target0
{
    float3 dir = normalize(input.view_ray);

    float3 ground_color = float3(0.3, 0.3, 0.4);
    float3 color;
    if (dir.y < 0.0) {
        color = ground_color;
    } else {
        float t = saturate(dir.y * 0.9);
        color = lerp(horizon_color, zenith_color, t);
    }
    return float4(color.rgb, 1.0);
}
