#include "../CommonHF/dvrHF.hlsli"

#ifdef SLICER_BUFFERS
#ifdef WITHOUT_KB
	SLICER_BUFFERS and WITHOUT_KB are exclusive
#endif
#ifdef CURVED_PLANE
#include "../CommonHF/curvedSlicerHF.hlsli"
#endif

Texture2D<uint> counter_mask_distmap : register(t0);
Texture2D<uint4> layer_packed0_RGBA : register(t1);
Texture2D<uint2> layer_packed1_RG : register(t2);
#endif

#ifdef WITHOUT_KB
#ifdef SLICER_BUFFERS
SLICER_BUFFERS and WITHOUT_KB are exclusive
#endif
#endif


[numthreads(DVR_BLOCKSIZE, DVR_BLOCKSIZE, 1)]
void main(uint2 Gid : SV_GroupID, uint2 DTid : SV_DispatchThreadID, uint groupIndex : SV_GroupIndex)
{	
    ShaderCamera camera = GetCamera();

	const uint2 pixel = DTid.xy;
	const bool pixel_valid = (pixel.x < camera.internal_resolution.x) && (pixel.y < camera.internal_resolution.y);
    if (!pixel_valid)
    {
        return;
    }

#ifndef CURVED_PLANE
	const float2 clipspace = mul((camera.inverse_vp), float4((float2)pixel + (float2)0.5 + float2(0, -0), 0, 1)).xy;
	if (clipspace.x < -1 || clipspace.x > 1 || clipspace.y < -1 || clipspace.y > 1)
	{
		return;
	}
	//const float2 uv = ((float2)pixel + (float2)0.5) * camera.internal_resolution_rcp;
	//const float2 clipspace = uv_to_clipspace(uv);
	RayDesc ray = CreateCameraRay(clipspace);
#else
	RayDesc ray = CreateCurvedSlicerRay(pixel);
	if (ray.TMin >= FLT_MAX - 1)
	{
		return;
	}
#endif

	ray.Origin -= ray.Direction * camera.sliceThickness * 0.5f;

	VolumeInstance vol_instance = GetVolumeInstance();
	ShaderClipper clipper; // TODO
	clipper.Init();

	// sample_dist (in world space scale)

#ifndef ZERO_THICKNESS   
	// Ray Intersection for Clipping Box //
	float2 hits_t = ComputeVBoxHits(ray.Origin, ray.Direction, vol_instance.flags, vol_instance.mat_alignedvbox_ws2bs, clipper);
	// 1st Exit in the case that there is no ray-intersecting boundary in the volume box
	hits_t.y = min(camera.z_far, hits_t.y); // only available in orthogonal view (thickness slicer)
#ifdef SLICER_BUFFERS
	if (camera.sliceThickness > 0)
	{
		hits_t.y = min(camera.sliceThickness, hits_t.y);
	}
#endif
	int num_ray_samples = (int)((hits_t.y - hits_t.x) / vol_instance.sample_dist + 0.5f);
	if (num_ray_samples <= 0 || num_ray_samples > 100000)
	{
		// (num_ray_samples > 100000) means that camera or volume actor is placed at wrong location (NAN)
		//	so vol_instance.mat_alignedvbox_ws2bs has invalid values
		return;
	}

#else // #ifdef ZERO_THICKNESS
	if (!IsInsideClipBox(ray.Origin, vol_instance.mat_alignedvbox_ws2bs))
		return;
#endif

	ShaderMaterial material = load_material(vol_instance.materialIndex);

	int texture_index_volume_main = material.volume_textures[VOLUME_MAIN_MAP].texture_descriptor;
	int texture_index_volume_mask = material.volume_textures[VOLUME_SEMANTIC_MAP].texture_descriptor;
	int texture_index_otf = material.lookup_textures[push.target_otf_slot].texture_descriptor; // LOOKUP_OTF
	int buffer_index_bitmask = push.bitmaskbuffer;

	if (texture_index_volume_main < 0)
		return;
	
	Texture3D volume_main = bindless_textures3D[descriptor_index(texture_index_volume_main)];
	Texture3D volume_mask = bindless_textures3D[descriptor_index(texture_index_volume_mask)];
	Texture3D volume_blocks = bindless_textures3D[descriptor_index(vol_instance.texture_volume_blocks)];
	Texture2D otf = bindless_textures[descriptor_index(texture_index_otf)];

	Buffer<uint> buffer_bitmask = bindless_buffers_uint[descriptor_index(buffer_index_bitmask)];

	RWTexture2D<float4> inout_color = bindless_rwtextures[descriptor_index(push.inout_color_Index)];
    
#ifdef ZERO_THICKNESS // using SLICER_BUFFERS
	uint c_m_d = counter_mask_distmap[pixel];
	//num_frags = c_m_d & 0xFF;
	uint mask = (c_m_d >> 8) & 0xFF;

	half4 prev_color = half4(saturate(inout_color[pixel].rgb), (half)1.f);
	float3 pos_sample_ts = TransformPoint(ray.Origin, vol_instance.mat_ws2ts);

	float sample_v = volume_main.SampleLevel(sampler_linear_wrap, pos_sample_ts, 0).r;

	half4 color = ApplyOTF(otf, sample_v, 0, (half)push.opacity_correction);

	if (mask & (SLICER_DEPTH_OUTLINE | SLICER_DEPTH_OUTLINE_DIRTY))
	{
		prev_color.a = (half)0.8f;
	}
	else if (mask & SLICER_SOLID_FILL_PLANE)
	{
		prev_color.a = (half)0.3f;
	}
	else if (mask & SLICER_DEBUG)
	{
		prev_color.a = (half)1.f;
	}
	else 
	{
		prev_color.a = 0;
	}
	//prev_color.rgb *= prev_color.a;
	color = prev_color + color * ((half)1.f - prev_color.a);

	inout_color[pixel] = color;// (float4)prev_color;
	return;
#else

	int hit_step = -1;
	float3 pos_start_ws = ray.Origin + ray.Direction * hits_t.x;
    float3 dir_sample_ws = ray.Direction * vol_instance.sample_dist;

#ifndef XRAY
	{
		const float3 singleblock_size_ts = vol_instance.ComputeSingleBlockTS();
		const uint2 blocks_wwh = uint2(vol_instance.num_blocks.x, vol_instance.num_blocks.x * vol_instance.num_blocks.y);

		SearchForemostSurface(hit_step, pos_start_ws, dir_sample_ws, num_ray_samples, vol_instance.mat_ws2ts, singleblock_size_ts, blocks_wwh, volume_main, buffer_bitmask
#if defined(OTF_MASK) || defined(SCULPT_MASK)
			, volume_mask
#endif
		);

		if (hit_step < 0)
		{
			return;
		}

		float3 pos_hit_ws = pos_start_ws + dir_sample_ws * (float)hit_step;
		if (hit_step > 0) {
			RefineSurface(pos_hit_ws, pos_hit_ws, dir_sample_ws, ITERATION_REFINESURFACE, vol_instance.mat_ws2ts, volume_main
#if defined(OTF_MASK) || defined(SCULPT_MASK)
				, volume_mask
#endif				
			);
			// unintended refinement that moves backward posterior to the starting point
			if (dot(pos_hit_ws - pos_start_ws, dir_sample_ws) <= 0)
				pos_hit_ws = pos_start_ws;

			pos_hit_ws -= dir_sample_ws;
		}

		float3 vec_o2start = pos_hit_ws - ray.Origin;

		// TODO : PIXELMASK for drawing outline (if required!!)
		// 	store a value to the PIXEL MASK (bitpacking...)
		//	use RWBuffer<UINT> atomic operation...

#ifdef WITHOUT_KB
		// NOTE:
		// The linear_depth is a normalized depth [0, 1]
		//  where the depth is defined along the z-axis from the plane where CAMERA places
		//	refer to "view_resolveCS.hlsl" 152-th line
		float3 cam_forward = camera.forward; // supposed to be a unit vector
		float z_hit = dot(vec_o2start, cam_forward) + camera.z_near;
		float linear_depth = z_hit * camera.z_far_rcp;

		RWTexture2D<float> inout_linear_depth = bindless_rwtextures_float[descriptor_index(push.inout_linear_depth_Index)];
		float prev_linear_depth = inout_linear_depth[pixel];
		if (linear_depth >= prev_linear_depth)
		{
			return;
		}
		inout_linear_depth[pixel] = linear_depth;
#endif

		// dvr depth??
		// inlinear depth , normal depth to ... tiled...
		// dominant light 1 and light field for multiple lights
		// tiled lighting?!
		// ... light map ...
		half opacity_correction = (half)push.opacity_correction;
		half sample_dist = (half)vol_instance.sample_dist;

		half4 color_out = (half4)0; // output

		uint num_frags = 0;
		Fragment fs[K_NUM];

#ifdef SLICER_BUFFERS
		// ORGONAL CASE 
		//	cam_forward is parallel with dir_sample_ws
		//	fragment z and zthick is computed w.r.t. the ray from the near-plane

		uint c_m_d = counter_mask_distmap[pixel];
		num_frags = c_m_d & 0xFF;
		uint mask = (c_m_d >> 8) & 0xFF;

		if (mask & (SLICER_DEPTH_OUTLINE_DIRTY | SLICER_DEPTH_OUTLINE))
		{
			return;
		}

		Fragment f_0, f_1;
		f_0.Init();
		f_1.Init();
		if (num_frags > 0)
		{
			uint4 v_layer_packed0_RGBA = layer_packed0_RGBA[pixel];

			f_0.Unpack_8bitUIntRGBA(v_layer_packed0_RGBA.r);
			f_0.z = asfloat(v_layer_packed0_RGBA.g);
			f_0.Unpack_Zthick_AlphaSum(v_layer_packed0_RGBA.b);

			if (num_frags > 1)
			{
				uint2 v_layer_packed1_RG = layer_packed1_RG[pixel];
				f_1.Unpack_8bitUIntRGBA(v_layer_packed0_RGBA.a);
				f_1.z = asfloat(v_layer_packed1_RG.r);
				f_1.Unpack_Zthick_AlphaSum(v_layer_packed1_RG.g);
			}
		}
		fs[0] = f_0;
		fs[1] = f_1;
#endif

#ifdef WITHOUT_KB
		float cos = dot(cam_forward, ray.Direction);
		if (prev_linear_depth < 1.f)
		{
			Fragment f;
			float3 prev_color_10 = inout_color[pixel].rgb;
			f.color = half4(prev_color_10.rgb, (half)1.f);
			float z = prev_linear_depth * camera.z_far - camera.z_near;
			f.z = z / cos;	// along the ray-caster's ray direction
			f.zthick = sample_dist;
			f.opacity_sum = (half)1.f;
			fs[0] = f;
			num_frags++;
		}
		fs[num_frags].Init();
#endif

		uint dvr_hit_enc = length(pos_hit_ws - pos_start_ws) < vol_instance.sample_dist ? DVR_SURFACE_ON_CLIPPLANE : DVR_SURFACE_OUTSIDE_CLIPPLANE;

		if (vol_instance.flags & INST_JITTERING)
		{
			RNG rng;
			rng.init(uint2(pixel), GetFrameCount());
			// additional feature : https://koreascience.kr/article/JAKO201324947256830.pdf
			float ray_dist_jitter = rng.next_float() * vol_instance.sample_dist;
			pos_hit_ws -= ray_dist_jitter * ray.Direction;
			vec_o2start = pos_hit_ws - ray.Origin;
		}
		float ray_dist_o2start = length(vec_o2start);

		// TODO: PROGRESSIVE SCHEME
		// light map can be updated asynch as long as it can be used as UAV
		// 1. two types of UAVs : lightmap (using mesh's lightmap and ?!)


		uint index_frag = 0;
		Fragment f_next_layer = fs[0];

		float3 dir_sample_ts = TransformVector(dir_sample_ws, vol_instance.mat_ws2ts);
		float3 dir_sample_ts_rcp = safe_rcp3(dir_sample_ts);
		float3 pos_ray_start_ts = TransformPoint(pos_hit_ws, vol_instance.mat_ws2ts);

		// --- gradient setting ---
		float3 v_v = dir_sample_ts;
		float3 uv_v = ray.Direction; // uv_v
		float3 uv_u = camera.up;
		float3 uv_r = cross(uv_v, uv_u); // uv_r
		uv_u = normalize(cross(uv_r, uv_v)); // uv_u , normalize?! for precision
		float3 v_u = TransformVector(uv_u * vol_instance.sample_dist, vol_instance.mat_ws2ts); // v_u
		float3 v_r = TransformVector(uv_r * vol_instance.sample_dist, vol_instance.mat_ws2ts); // v_r
		// -------------------------

		int start_step = 0;
		float sample_value = volume_main.SampleLevel(sampler_linear_clamp, pos_ray_start_ts, 0).r;
		float sample_value_prev = volume_main.SampleLevel(sampler_linear_clamp, pos_ray_start_ts - v_v, 0).r;

		if (dvr_hit_enc == DVR_SURFACE_ON_CLIPPLANE) // on the clip plane
		{
			half4 color = (half4)0;
			start_step++;

			// unlit here
#ifdef OTF_PREINTEGRATION
			if (Vis_Volume_And_Check_Slab(color, sample_value, sample_value_prev, pos_ray_start_ts, opacity_correction, volume_main, otf))
#else
			if (Vis_Volume_And_Check(color, sample_value, pos_ray_start_ts, opacity_correction, volume_main, otf))
#endif
			{
				IntermixSample(color_out, f_next_layer, index_frag, color, ray_dist_o2start, sample_dist, num_frags, fs);
			}
			sample_value_prev = sample_value;
		}

		int sample_count = 0;

		// load the base light 
		//uint bucket = 0;
		//uint bucket_bits = xForwardLightMask[bucket];
		//const uint bucket_bit_index = firstbitlow(bucket_bits);
		//const uint entity_index = bucket * 32 + bucket_bit_index;
		//ShaderEntity base_light = load_entity(lights().first_item() + entity_index);
		ShaderEntity base_light = load_entity(0);
		float3 L = (float3)base_light.GetDirection();
		float3 V = -ray.Direction;

		// in this version, simply consider the directional light
		[loop]
		for (int step = start_step; step < num_ray_samples; step++)
		{
			float3 pos_sample_ts = pos_ray_start_ts + dir_sample_ts * (float)step;

			LOAD_BLOCK_INFO(blkSkip, pos_sample_ts, dir_sample_ts_rcp, num_ray_samples, step, buffer_bitmask)

			[branch]
			if (blkSkip.visible)
			{
				[loop]
				for (int sub_step = 0; sub_step <= blkSkip.num_skip_steps; sub_step++)
				{
					float3 pos_sample_blk_ts = pos_ray_start_ts + dir_sample_ts * (float)(step + sub_step);

					half4 color = (half4)0;
					if (sample_value_prev < 0) {
						sample_value_prev = volume_main.SampleLevel(sampler_linear_clamp, pos_sample_blk_ts - v_v, 0).r;
					}
					sample_count++;
#if OTF_PREINTEGRATION
					if (Vis_Volume_And_Check_Slab(color, sample_value, sample_value_prev, pos_sample_blk_ts, opacity_correction, volume_main, otf))
#else
					if (Vis_Volume_And_Check(color, sample_value, pos_sample_blk_ts, opacity_correction, volume_main, otf))
#endif
					{
						float3 G = GradientVolume3(sample_value, sample_value_prev, pos_sample_blk_ts,
							v_v, v_u, v_r, uv_v, uv_u, uv_r, volume_main);
						float length_G = length(G);

						half lighting = (half)1.f;
						if (length_G > 0) {
							// TODO using material attributes
							float3 N = G / length_G;
							lighting = (half)saturate(PhongBlinnVR(V, L, N, float4(0.3, 0.3, 1.0, 100)));

							// TODO
							// 
							// Surface surface;
							// surface.init();
							// TiledLighting or ForwardLighting
						}

						color = half4(lighting * color.rgb, color.a);
						float ray_dist = ray_dist_o2start + (float)(step + sub_step) * vol_instance.sample_dist;
						IntermixSample(color_out, f_next_layer, index_frag, color, ray_dist, sample_dist, num_frags, fs);

						if (color_out.a >= ERT_ALPHA_HALF)
						{
							sub_step = num_ray_samples;
							step = num_ray_samples;
							color_out.a = (half)1.f;
							break;
						}
					} // if (Vis_Volume_And_...
					sample_value_prev = sample_value;
				} // for (int sub_step = 0; sub_step <= blkSkip.num_skip_steps; sub_step++)
			}
			else
			{
				sample_value_prev = -1;
			} // if (blkSkip.visible)
			step += blkSkip.num_skip_steps;
			//step -= 1;
		} // for (int step = start_step; step < num_ray_samples; step++)

		if (color_out.a < ERT_ALPHA_HALF)
		{
			for (; index_frag < num_frags; ++index_frag)
			{
				half4 color = fs[index_frag].color;
				color_out += color * ((half)1.f - color_out.a);
			}
		}

		inout_color[pixel] = (float4)color_out;
	}
#else	// XRAY
	{
		half opacity_correction = (half)push.opacity_correction;
		float depth_out = FLT_MAX;
		float3 pos_ray_start_ts = TransformPoint(pos_start_ws, vol_instance.mat_ws2ts);
		float depth_begin = depth_out = length(pos_start_ws - ray.Origin);
		float3 dir_sample_ts = TransformVector(dir_sample_ws, vol_instance.mat_ws2ts);
		float3 dir_sample_ts_rcp = safe_rcp3(dir_sample_ts);

#if defined(MAX_RAY) || defined(MIN_RAY)
		RNG rng;
		rng.init(uint2(pixel), GetFrameCount());
		// additional feature : https://koreascience.kr/article/JAKO201324947256830.pdf
		int luckyStep = (int)(rng.next_float() * (float)num_ray_samples);
		float depth_sample = depth_begin + vol_instance.sample_dist * (float)(luckyStep);
		float3 pos_lucky_sample_ws = pos_start_ws + dir_sample_ws * (float)luckyStep;
		float3 pos_lucky_sample_ts = TransformPoint(pos_lucky_sample_ws, g_cbVobj.mat_ws2ts);
#ifdef MIN_RAY
		float sample_v_prev = 1.f;
#else
		float sample_v_prev = 0;
#endif

#ifdef OTF_MASK
		float3 pos_mask_sample_ts = pos_lucky_sample_ts;
#endif

#else // ~(defined(MAX_RAY) || defined(MIN_RAY)), which means RAY_SUM
		float depth_sample = depth_begin + vol_instance.sample_dist * (float)(num_ray_samples);
		int num_valid_samples = 0;
		float4 vis_otf_sum = (float4)0;
#endif

		int count = 0;
		[loop]
		for (uint i = 0; i < num_ray_samples; i++)
		{
			float3 pos_sample_ts = pos_ray_start_ts + dir_sample_ts * (float)i;

#if defined(MAX_RAY) || defined(MIN_RAY)
			LOAD_BLOCK_INFO(blkSkip, pos_sample_ts, dir_sample_ts_rcp, num_ray_samples, i, buffer_bitmask)
#ifdef MAX_RAY
				if (blkSkip.blk_value > sample_v_prev)
#else MIN_RAY
				if (blkSkip.blk_value < sample_v_prev)
#endif
				{
					count++;
					for (int k = 0; k <= blkSkip.num_skip_steps; k++)
					{
						float3 pos_sample_in_blk_ts = pos_ray_start_ts + dir_sample_ts * (float)(i + k);
						float sample_v = volume_main.SampleLevel(sampler_linear_clamp, pos_sample_in_blk_ts, 0).r;
#ifdef MAX_RAY
						if (sample_v > sample_v_prev)
#else
						if (sample_v < sample_v_prev)
#endif
						{
#ifdef OTF_MASK
							pos_mask_sample_ts = pos_sample_in_blk_ts;
#endif
							sample_v_prev = sample_v;
							depth_sample = depth_begin + vol_instance.sample_dist * (float)i;
						}
					}
				}
			i += blkSkip.num_skip_steps;
			// this is for outer loop's i++
			//i -= 1;
#else	// ~(defined(MAX_RAY) || defined(MIN_RAY)), which means RAY_SUM
			float sample_v = volume_main.SampleLevel(sampler_linear_clamp, pos_sample_ts, 0).r;
#ifdef OTF_MASK
			float id = volume_mask.SampleLevel(sampler_point_wrap, pos_sample_ts, 0).r;
			float4 vis_otf = (float4)ApplyOTF(otf, sample_v, id * vol_instance.mask_unormid_otf_map, opacity_correction);
#else
			float4 vis_otf = (float4)ApplyOTF(otf, sample_v, 0, opacity_correction);
#endif
			// otf sum is necessary for multi-otf case (tooth segmentation-out case)
			//if (vis_otf.a > 0) // results in discontinuous visibility caused by aliasing problem
			{
				vis_otf_sum += vis_otf;
				num_valid_samples++;
			}
#endif
		}

#if defined(MAX_RAY) || defined(MIN_RAY)
#ifdef OTF_MASK
		float id = volume_mask.SampleLevel(sampler_point_wrap, pos_sample_ts, 0).r;
		half4 vis_otf = ApplyOTF(otf, sample_v_prev, id * vol_instance.mask_unormid_otf_map, opacity_correction);
#else
		half4 vis_otf = ApplyOTF(otf, sample_v_prev, 0, opacity_correction);
#endif
#else 
		if (num_valid_samples == 0)
			num_valid_samples = 1;
		half4 vis_otf = (half)(vis_otf_sum / (float)num_valid_samples);
#endif

		half4 color_out = (half4)0; // output

		uint num_frags = 0;
		Fragment fs[K_NUM];

#ifdef WITHOUT_KB
		float cos = dot(camera.forward, ray.Direction);
		RWTexture2D<float> inout_linear_depth = bindless_rwtextures_float[descriptor_index(push.inout_linear_depth_Index)];
		float prev_linear_depth = inout_linear_depth[pixel];

		if (prev_linear_depth < 1.f)
		{
			Fragment f;
			float4 prev_color_10 = inout_color[pixel].rgba;
			f.color = half4(prev_color_10.rgb, (half)1.f);
			float z = prev_linear_depth * camera.z_far - camera.z_near;
			f.z = z / cos;
			f.zthick = (half)vol_instance.sample_dist;
			f.opacity_sum = (half)1.f;
			fs[0] = f;
			num_frags++;
		}
		fs[num_frags].Init();
#endif

#ifdef SLICER_BUFFERS
		// ORGONAL CASE 
		//	cam_forward is parallel with dir_sample_ws
		//	fragment z and zthick is computed w.r.t. the ray from the near-plane

		uint c_m_d = counter_mask_distmap[pixel];
		num_frags = c_m_d & 0xFF;
		uint mask = (c_m_d >> 8) & 0xFF;

		if (mask & (SLICER_DEPTH_OUTLINE_DIRTY | SLICER_DEPTH_OUTLINE))
		{
			return;
		}

		Fragment f_0, f_1;
		f_0.Init();
		f_1.Init();
		if (num_frags > 0)
		{
			uint4 v_layer_packed0_RGBA = layer_packed0_RGBA[pixel];

			f_0.Unpack_8bitUIntRGBA(v_layer_packed0_RGBA.r);
			f_0.z = asfloat(v_layer_packed0_RGBA.g);
			f_0.Unpack_Zthick_AlphaSum(v_layer_packed0_RGBA.b);

			if (num_frags > 1)
			{
				uint2 v_layer_packed1_RG = layer_packed1_RG[pixel];
				f_1.Unpack_8bitUIntRGBA(v_layer_packed0_RGBA.a);
				f_1.z = asfloat(v_layer_packed1_RG.r);
				f_1.Unpack_Zthick_AlphaSum(v_layer_packed1_RG.g);
			}
		}
		fs[0] = f_0;
		fs[1] = f_1;
#endif

		uint index_frag = 0;
		Fragment f_next_layer = fs[0]; // if no frag, the z-depth is infinite

		IntermixSample(color_out, f_next_layer, index_frag, vis_otf, depth_sample, (half)(hits_t.y - hits_t.x), num_frags, fs);

		if (color_out.a < ERT_ALPHA_HALF)
		{
			for (; index_frag < num_frags; ++index_frag)
			{
				half4 color = fs[index_frag].color;
				color_out += color * ((half)1.f - color_out.a);
			}
		}
		inout_color[pixel] = (float4)color_out;
	}
#endif 
#endif
}