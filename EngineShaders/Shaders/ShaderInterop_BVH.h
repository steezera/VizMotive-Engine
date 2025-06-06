#ifndef SHADERINTEROP_BVH_H
#define SHADERINTEROP_BVH_H
#include "ShaderInterop.h"

struct BVHPushConstants
{
	uint geometryIndex;
	uint subsetIndex;
	uint primitiveCount;
	uint instanceIndex;

	// GEOMETRYSPACE only (for a single geometry)
	float3 aabb_min;
	uint vb_pos_w;
	float3 aabb_extents_rcp;	// enclosing AABB 1.0f / abs(max - min)
	uint ib;
};

static const uint BVH_BUILDER_GROUPSIZE = 64;

// lower 8-bits in the flags are for instance masking
static const uint BVH_PRIMITIVE_FLAG_DOUBLE_SIDED = 1 << 8;
static const uint BVH_PRIMITIVE_FLAG_TRANSPARENT = 1 << 9;

struct BVHPrimitive
{
	uint2 packed_prim;
	uint flags;
	float x0;

	float y0;
	float z0;
	float x1;
	float y1;

	float z1;
	float x2;
	float y2;
	float z2;

	float3 v0() { return float3(x0, y0, z0); }
	float3 v1() { return float3(x1, y1, z1); }
	float3 v2() { return float3(x2, y2, z2); }

#ifndef __cplusplus
	PrimitiveID primitiveID()
	{
		PrimitiveID prim;
		prim.init();
		prim.unpack2(packed_prim);
		return prim;
	}
#endif // __cplusplus
};

struct BVHNode
{
	float3 min;
	uint LeftChildIndex;
	float3 max;
	uint RightChildIndex;
};

#endif // SHADERINTEROP_BVH_H
