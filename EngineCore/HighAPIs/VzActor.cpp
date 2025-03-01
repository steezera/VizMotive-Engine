#include "VzEngineAPIs.h"
#include "Components/Components.h"
#include "Utils/Backlog.h"

using namespace vz;
using namespace std;
using namespace backlog;

namespace vzm
{
#define GET_RENDERABLE_COMP(COMP, RET) RenderableComponent* COMP = compfactory::GetRenderableComponent(componentVID_); \
	if (!COMP) {post("RenderableComponent(" + to_string(componentVID_) + ") is INVALID!", LogLevel::Error); return RET;}

	void VzBaseActor::SetVisibleLayerMask(const uint8_t layerBits, const uint8_t maskBits)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetVisibleMask(layerBits, maskBits);
		UpdateTimeStamp();
	}
}

namespace vzm
{
	bool VzActor::IsRenderable() const
	{
		GET_RENDERABLE_COMP(renderable, false);
		return renderable->IsMeshRenderable() || renderable->IsVolumeRenderable();
	}
	void VzActor::SetGeometry(const GeometryVID vid)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetGeometry(vid);
		UpdateTimeStamp();
	}
	void VzActor::SetMaterial(const MaterialVID vid, const int slot)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetMaterial(vid, slot);
		UpdateTimeStamp();
	}
	void VzActor::SetMaterials(const std::vector<MaterialVID> vids)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetMaterials(vids);
		UpdateTimeStamp();
	}
	void VzActor::EnableCastShadows(const bool enabled)
	{
		assert(0 && "TODO");
		UpdateTimeStamp();
	}
	void VzActor::EnableReceiveShadows(const bool enabled)
	{
		assert(0 && "TODO");
		UpdateTimeStamp();
	}


	void VzActor::EnableSlicerSolidFill(const bool enabled)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->EnableSlicerSolidFill(enabled);
		UpdateTimeStamp();
	}

	void VzActor::EnableClipper(const bool clipBoxEnabled, const bool clipPlaneEnabled)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->EnableClipper(clipBoxEnabled, clipPlaneEnabled);
	}
	void VzActor::SetClipPlane(const vfloat4& clipPlane)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetClipPlane(*(XMFLOAT4*)&clipPlane);
	}
	void VzActor::SetClipBox(const vfloat4x4& clipBox)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetClipBox(*(XMFLOAT4X4*)&clipBox);
	}
	bool VzActor::IsClipperEnabled(bool* clipBoxEnabled, bool* clipPlaneEnabled) const
	{
		GET_RENDERABLE_COMP(renderable, false);
		bool box_clipped = renderable->IsBoxClipperEnabled();
		bool plane_clipped = renderable->IsPlaneClipperEnabled();
		if (clipBoxEnabled) *clipBoxEnabled = box_clipped;
		if (clipPlaneEnabled) *clipPlaneEnabled = plane_clipped;
		return box_clipped || plane_clipped;
	}

	void VzActor::SetOutineThickness(const float v)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetOutineThickness(v);
	}
	void VzActor::SetOutineColor(const vfloat3 v)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetOutineColor(*(XMFLOAT3*)&v);
	}
	void VzActor::SetOutineThreshold(const float v)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetOutineThreshold(v);
	}
	void VzActor::SetUndercutDirection(const vfloat3 v)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetUndercutDirection(*(XMFLOAT3*)&v);
	}
	void VzActor::SetUndercutColor(const vfloat3 v)
	{
		GET_RENDERABLE_COMP(renderable, );
		renderable->SetUndercutColor(*(XMFLOAT3*)&v);
	}

	std::vector<MaterialVID> VzActor::GetMaterials() const
	{
		GET_RENDERABLE_COMP(renderable, std::vector<MaterialVID>());
		return renderable->GetMaterials();
	}
	MaterialVID VzActor::GetMaterial(const int slot) const
	{
		GET_RENDERABLE_COMP(renderable, INVALID_VID);
		return renderable->GetMaterial(slot);
	}
	GeometryVID VzActor::GetGeometry() const
	{
		GET_RENDERABLE_COMP(renderable, INVALID_VID);
		return renderable->GetGeometry();
	}
}