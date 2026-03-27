module ecs::entity;

import ecs::archetype;
import ecs::entity_index;
import ecs::world;
import ecs::types;

fn bool is_pair(Id id) @inline {
	return id < entity_index::GENERATION_MASK;
}

fn Id ecs_pair(Entity first, Entity second) @inline {
	ulong first_id = entity_index::entity_id_low(first);
	ulong second_id = entity_index::entity_id_low(second);

	return second_id | (first_id << entity_index::ENTITY_BITS);
}

fn Entity pair_first(Id pair) @inline {
	return entity_index::entity_id_low(pair >> entity_index::ENTITY_BITS);
}

fn Entity pair_second(Id pair) @inline {
	return entity_index::entity_id_low(pair);
}

fn Entity create_new_id(World* world) {
	Entity new_entity = world.entity_index.new_entity()!!;
	EntityRecord* record = world.entity_index.entity_record_ensure(new_entity);

	record.archetype = world.root_archetype;
	record.archetype_row = 0;
	return new_entity;
}

fn void entity_add_id(World* world, Entity entity, Id id) {
	EntityRecord*? record = world.entity_index.entity_record_get_alive(entity);
	if (catch record) return;

	Archetype* source = record.archetype;

	bool has_component = source.has_component(id);
	if (has_component) {
		return;
	}

	Archetype* destination;

	if (is_pair(id)) {
		// TODO: handle pairs
	} else {
		destination = archetype::archetype_find_with(world, source, id);
	}

	if (destination == world.root_archetype) {
		archetype::archetype_insert_entity(destination, entity, record);
	} else {
		archetype::archetype_move_entity(world, source, destination, entity, record);
	}
}

fn void entity_set_id(World* world, Entity entity, Id id, void* data) {
	EntityRecord*? record = world.entity_index.entity_record_get_alive(entity);
	if (catch record) return;
	
	Archetype* source = record.archetype;
	ArchetypeColumn*? data_column = source.get_column(id);
	
	if (try data_column) {
		archetype::archetype_modify_column(data_column, record.archetype_row, data);
		return;
	}

	Archetype* destination;

	if (is_pair(id)) {
		// TODO: handle pairs
	} else {
		destination = archetype::archetype_find_with(world, source, id);
	}

	if (destination == world.root_archetype) {
		archetype::archetype_insert_entity(destination, entity, record);
	} else {	
		archetype::archetype_move_entity(world, source, destination, entity, record);
	}

	ArchetypeColumn*? added_column = destination.get_column(id);
	if(catch added_column) {
		unreachable("column not found in destination archetype");
	}

	archetype::archetype_modify_column(added_column, record.archetype_row, data);
}

fn bool entity_has_id(World* world, Entity entity, Id id) {
	EntityRecord*? record = world.entity_index.entity_record_get_alive(entity);
	if (catch record) return false;

	Archetype* source = record.archetype;
	return source.has_component(id);
}


macro entity_add(World* world, Entity entity, $Type) {
	Id? id = world.type_component_lookup.get($Type.typeid);
	if (catch id) unreachable("component id not found");

	entity_add_id(world, entity, id);
}

macro entity_set(World* world, Entity entity, $Type, value) {
	Id? id = world.type_component_lookup.get($Type.typeid);
	if (catch id) unreachable("component id not found");

	entity_set_id(world, entity, id, &value);
}

macro bool entity_has(World* world, Entity entity, $Type) {
	Id? id = world.type_component_lookup.get($Type.typeid);
	if (catch id) unreachable("component id not found");

	return entity_has_id(world, entity, id);
}

fn void entity_remove() {}

fn void entity_delete() {}