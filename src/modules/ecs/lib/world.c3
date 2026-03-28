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

const uint ECS_WILDCARD 		= MAX_COMPONENTS + 1;
const uint ECS_CHILDOF 			= MAX_COMPONENTS + 2;
const uint ECS_NAME				= MAX_COMPONENTS + 3;
const uint ECS_COMPONENT 		= MAX_COMPONENTS + 4;
const uint ECS_REST				= MAX_COMPONENTS + 5;
const uint ECS_FORCE_TAG 		= MAX_COMPONENTS + 6;

typedef EcsName = String;

struct World {
	Allocator allocator;

	EntityIndex entity_index;
	SparseList{Archetype} archetype_index;
	SparseList{ComponentRecord} component_index;

	HashMap{typeid, Component} type_component_lookup;
	HashMap{Component, TypeInfo} component_infos;

	HashMap{Id, ComponentRecord*} components_map;
	HashMap{ArchetypeType, Archetype*} archetypes_map;

	Archetype* root_archetype;
	Component next_component;
}

fn Component new_component(World* world, TypeInfo type_info) {
	Component component = world.next_component++;
	assert(component < MAX_COMPONENTS, "max components reached");

   type_info.component = component;
   world.component_infos.set(component, type_info);
	entity::entity_add_id(world, component, ECS_COMPONENT);
   return component;
}

fn Entity new_tag(World* world, TypeInfo type_info) {
   Entity tag = world.next_component++;
   assert(tag < MAX_COMPONENTS, "max components reached");

   type_info.component = tag;
   world.component_infos.set(tag, type_info);
   return tag;
}

macro register_component(World* world, Component component, $Type) {
   TypeInfo type_info = {
		.type_size = $Type.sizeof,
		.alignment = $Type.alignof,

		.component = component,
		.name = $Type.nameof,
	};

   world.component_infos.set(component, type_info);
	world.type_component_lookup.set($Type.typeid, component);
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

   register_component(self, ECS_NAME, EcsName);

   entity::entity_set_id(self, ECS_WILDCARD, ECS_NAME, "EcsWildcard");
   entity::entity_set_id(self, ECS_CHILDOF, ECS_NAME, "EcsChildOf");
   entity::entity_set_id(self, ECS_COMPONENT, ECS_NAME, "EcsComponent");
   entity::entity_set_id(self, ECS_REST, ECS_NAME, "EcsRest");
   entity::entity_set_id(self, ECS_FORCE_TAG, ECS_NAME, "EcsForceTag");
   entity::entity_set_id(self, ECS_NAME, ECS_NAME, "EcsName");
   entity::entity_set_id(self, ECS_WILDCARD, ECS_NAME, "EcsWildcard");
   entity::entity_set_id(self, ECS_CHILDOF, ECS_NAME, "EcsChildOf");
   entity::entity_set_id(self, ECS_COMPONENT, ECS_NAME, "EcsComponent");
   entity::entity_set_id(self, ECS_REST, ECS_NAME, "EcsRest");
   entity::entity_set_id(self, ECS_FORCE_TAG, ECS_NAME, "EcsForceTag");
}

fn void World.free(&self) {
   // TODO: free archetypes
   self.entity_index.free();
   self.archetype_index.free();
   self.component_index.free();
   self.archetypes_map.free();
}

macro Component World.component(&self, $Type) {
	TypeInfo type_info = {
		.type_size = $Type.sizeof,
		.alignment = $Type.alignof,

		.component = component,
		.name = $Type.nameof,
	};

   	Component component = new_component();
	self.type_component_lookup.set($Type.typeid, component);
	return component;
}

macro Entity World.tag(&self, $Type) {
	TypeInfo type_info = {
		.type_size = $Type.sizeof,
		.alignment = $Type.alignof,

		.component = component,
		.name = $Type.nameof,
	};

   	Component tag = new_tag();
	self.type_component_lookup.set($Type.typeid, tag);
	return tag;
}

fn Entity World.entity(&self) {
   Entity entity = entity::create_new_id(self);
   return entity;
}

macro World.add(&self, Entity entity, $Type) {
	entity::entity_add(self, entity, $Type);
}

macro World.set(&self, Entity entity, $Type, value) {
	entity::entity_set(self, entity, $Type, value);
}

macro bool World.has(&self, Entity entity, $Type) {
	return entity::entity_has(self, entity, $Type);
}

macro World.get(&self, Entity entity, $Type) {
	return entity::entity_get(self, entity, $Type);
}

macro World.remove(&self, Entity entity, $Type) {
	entity::entity_remove(self, entity, $Type);
}

fn void World.delete(&self, Entity entity) {
	entity::entity_delete(self, entity);
}

