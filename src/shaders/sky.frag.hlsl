cbuffer SkyUniforms : register(b0, space3)
{
    float3 horizon_color;
    float _pad1;
    float3 zenith_color;
    float _pad2;
    float3 ground_color;
    float _pad3;
    float3 light_color;
    float _pad4;
    float3 light_direction;
};

struct Input
{
    float3 view_ray : TEXCOORD0;
};

float4 main(Input input) : SV_Target0
{
    float3 dir = normalize(input.view_ray);
    float3 sun_direction = normalize(light_direction);
    float sun_amount = dot(dir, sun_direction);

    float3 color;
    if (dir.y < 0.0) {
        color = ground_color;
    } else {
        float t = saturate(dir.y * 0.9);
        color = lerp(horizon_color, zenith_color, t);

        float sun_disc = smoothstep(0.994, 0.996, sun_amount);
        color = lerp(color, light_color, sun_disc);
    }
    return float4(color, 1.0);
}
