#include "RenderPath3D.h"
#include "Utils/ECS.h"
#include "Utils/Backlog.h"

namespace vz::canvas
{
	static std::unordered_map<Entity, std::unique_ptr<RenderPath3D>> renderPaths;

	Canvas* GetCanvas(const Entity entity)
	{
		auto it = renderPaths.find(entity);
		return it != renderPaths.end() ? it->second.get() : nullptr;
	}

	Canvas* GetFirstCanvasByName(const std::string& name)
	{
		for (auto& it : renderPaths) {
			if (it.second.get()->name == name) return it.second.get();
		}
		return nullptr;
	}

	RenderPath3D* CreateRenderPath3D(graphics::GraphicsDevice* graphicsDevice, const std::string& name, const Entity entity)
	{
		Entity ett = entity;
		if (entity == 0)
		{
			ett = ecs::CreateEntity();
		}

		renderPaths[ett] = std::make_unique<RenderPath3D>(ett, graphicsDevice);
		RenderPath3D* render_path = renderPaths[ett].get();
		render_path->name = name;
		return render_path;
	}

	bool DestroyCanvas(const Entity entity)
	{
		auto it = renderPaths.find(entity);
		if (it == renderPaths.end())
		{
			vzlog_error("Scene::DestroyCanvas >> Invalid Entity! (%llu)", entity);
			return false;
		}
		it->second.reset();
		renderPaths.erase(it);
		return true;
	}

	void DestroyAll()
	{
		renderPaths.clear();
	}
}