#pragma once
#include "VzComponentAPIs.h"

namespace vzm
{
	struct API_EXPORT VzScene : VzBaseComp
	{
	private:
		float iblRotation_ = 0.0f;
	public:
		VzScene(const VID vid, const std::string& originFrom)
			: VzBaseComp(vid, originFrom, COMPONENT_TYPE::SCENE) {
		}
		virtual ~VzScene() = default;

		//std::vector<VID> GetSceneCompChildren();
		//bool LoadIBL(const std::string& iblPath);
		//float GetIBLIntensity();
		//float GetIBLRotation();
		//void SetIBLIntensity(float intensity);
		//void SetIBLRotation(float rotation);
		//void SetSkyboxVisibleLayerMask(const uint8_t layerBits = 0x7, const uint8_t maskBits = 0x4);
		//void SetLightmapVisibleLayerMask(const uint8_t layerBits = 0x3, const uint8_t maskBits = 0x2); // check where to set

		void AppendChild(const VzBaseComp* child);
		void DetachChild(const VzBaseComp* child);
		void AttachToParent(const VzBaseComp* parent);

		const std::vector<VID>& GetChildrenVIDs() const;

		bool RenderChain(const std::vector<ChainUnitRCam>& rendererChain, const float dt = -1.f);
	};
}
