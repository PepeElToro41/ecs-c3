module ecs::world;

import std::collections::map;
import std::collections::list;

import ecs::component_index;
import ecs::types;
import ecs::sparse_list;
import ecs::archetype;
import ecs::archetype_type;
import ecs::entity;
import ecs::entity_index;

const uint MAX_COMPONENTS = 1024;

const uint ECS_WILDCARD = 		MAX_COMPONENTS + 1;
const uint ECS_CHILDOF = 		MAX_COMPONENTS + 2;
const uint ECS_NAME = 			MAX_COMPONENTS + 3;
const uint ECS_COMPONENT = 		MAX_COMPONENTS + 4;
const uint ECS_REST = 			MAX_COMPONENTS + 5;
const uint ECS_FORCE_TAG = 		MAX_COMPONENTS + 6;

// TODO: component records should have stable pointers

struct World {
	Allocator allocator;

	EntityIndex entity_index;
	SparseList{Archetype} archetype_index;
	HashMap{Id, ComponentRecord*} component_index;

	HashMap{typeid, Component} type_component_lookup;
	HashMap{Component, TypeInfo} component_infos;

	HashMap{ArchetypeType, Archetype} archetypes_map;

	Archetype* root_archetype;
	Component next_component;
}


fn void World.init(&self, Allocator allocator) {
	self.allocator = allocator;
	self.entity_index.init(allocator);
	self.archetype_index.init(allocator);
	self.component_index.init(allocator);
	self.archetypes_map.init(allocator);

	self.next_component = 1;

	@pool() {
		self.root_archetype = archetype::archetype_create(self, archetype_type::create_empty(tmem));
	};

	for (int i = 0; i < ECS_REST; i++) {
		entity::create_new_id(self);
	}
}

macro Component World.component(&self, $Type) {
	Component component = self.next_component++;
	assert(component < MAX_COMPONENTS, "max components reached");

	self.type_component_lookup.set($Type.typeid, component);

	entity::entity_set(self, component, ECS_COMPONENT);

	TypeInfo type_info = {
		.type_size = $Type.sizeof,
		.alignment = $Type.alignof,

		.component = component,
		.name = $Type.nameof,
	};

	return component;
}


macro Entity World.tag(&self, $Type) {
	Entity tag = self.next_component++;
	assert(component < MAX_COMPONENTS, "max components reached");

	self.type_component_lookup.set($Type.typeid, tag);

}
