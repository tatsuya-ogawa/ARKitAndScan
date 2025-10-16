//
//  Shaders.metal
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

// Camera background structures
struct CameraVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Mesh structures
struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float3 worldPosition;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

struct FragmentUniforms {
    uint mode;
    float outlineWidth;
    float outlineSoftness;
    float baseOpacity;
    float4 outlineColor;
};

// MARK: - Camera Background Shaders

vertex CameraVertexOut camera_vertex_shader(
    uint vertexID [[vertex_id]]
) {
    // Full-screen quad coordinates
    const float4 positions[6] = {
        float4(-1.0, -1.0, 0.0, 1.0),  // Bottom-left
        float4( 1.0, -1.0, 0.0, 1.0),  // Bottom-right
        float4(-1.0,  1.0, 0.0, 1.0),  // Top-left
        float4(-1.0,  1.0, 0.0, 1.0),  // Top-left
        float4( 1.0, -1.0, 0.0, 1.0),  // Bottom-right
        float4( 1.0,  1.0, 0.0, 1.0)   // Top-right
    };

    const float2 texCoords[6] = {
        float2(0.0, 1.0),  // Bottom-left
        float2(1.0, 1.0),  // Bottom-right
        float2(0.0, 0.0),  // Top-left
        float2(0.0, 0.0),  // Top-left
        float2(1.0, 1.0),  // Bottom-right
        float2(1.0, 0.0)   // Top-right
    };

    CameraVertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 camera_fragment_shader(
    CameraVertexOut in [[stage_in]],
    texture2d<float, access::sample> textureY [[texture(0)]],
    texture2d<float, access::sample> textureCbCr [[texture(1)]]
) {
    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

    // Sample Y and CbCr textures
    float y = textureY.sample(colorSampler, in.texCoord).r;
    float2 uv = textureCbCr.sample(colorSampler, in.texCoord).rg - float2(0.5, 0.5);

    // BT.709 YUV to RGB conversion with full-range inputs
    float r = y + 1.5748f * uv.y;
    float g = y - 0.1873f * uv.x - 0.4681f * uv.y;
    float b = y + 1.8556f * uv.x;

    return float4(r, g, b, 1.0);
}

// MARK: - Vertex Shader

vertex VertexOut mesh_vertex_shader(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(2)]]
) {
    VertexOut out;

    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;

    // Transform normal to world space
    float3x3 normalMatrix = float3x3(uniforms.modelMatrix[0].xyz,
                                      uniforms.modelMatrix[1].xyz,
                                      uniforms.modelMatrix[2].xyz);
    out.normal = normalize(normalMatrix * in.normal);
    out.worldPosition = worldPosition.xyz;

    return out;
}

// MARK: - Fragment Shader

fragment float4 mesh_fragment_shader(
    VertexOut in [[stage_in]],
    float3 barycentricCoord [[barycentric_coord]],
    constant FragmentUniforms &uniforms [[buffer(0)]]
) {
    // Simple lighting calculation
    float3 lightDirection = normalize(float3(0.5, 1.0, 0.5));
    float3 normal = normalize(in.normal);

    float diffuse = max(dot(normal, lightDirection), 0.0);
    float ambient = 0.3;

    float3 baseColor = float3(0.8, 0.8, 0.9);
    float3 shadedColor = baseColor * (ambient + diffuse * 0.7);

    // Edge detection using barycentric coordinates
    float3 width = fwidth(barycentricCoord);
    float3 smooth = smoothstep(float3(0.0), width * max(uniforms.outlineWidth, 0.001), barycentricCoord);
    float edgeFactor = min(smooth.x, min(smooth.y, smooth.z));
    edgeFactor = powr(edgeFactor, max(uniforms.outlineSoftness, 0.0001));
    float outlineMask = clamp(1.0 - edgeFactor, 0.0, 1.0);

    if (uniforms.mode == 1u) {
        float alpha = outlineMask * uniforms.outlineColor.a;
        return float4(uniforms.outlineColor.rgb, alpha);
    } else if (uniforms.mode == 2u) {
        float outlineContribution = outlineMask * uniforms.outlineColor.a;
        float3 mixedColor = mix(shadedColor, uniforms.outlineColor.rgb, clamp(outlineContribution, 0.0, 1.0));
        float alpha = max(uniforms.baseOpacity, outlineContribution);
        return float4(mixedColor, alpha);
    }

    return float4(shadedColor, uniforms.baseOpacity);
}
