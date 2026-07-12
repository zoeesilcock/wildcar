cbuffer SkyUniforms : register(b0, space1)
{
    float3 cam_forward;
    float tan_half_fov;
    float3 cam_right;
    float3 cam_up;
    float aspect;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 view_ray : TEXCOORD0;
};

VSOutput main(uint vertex_id : SV_VertexID)
{
    VSOutput output;
    float2 ndc = float2(
        (vertex_id == 2) ? 3.0 : -1.0,
        (vertex_id == 1) ? 3.0 : -1.0
    );
    output.position = float4(ndc, 1.0, 1.0);

    output.view_ray = cam_forward
        + cam_right * ndc.x * tan_half_fov * aspect
        + cam_up * ndc.y * tan_half_fov;

    return output;
}
