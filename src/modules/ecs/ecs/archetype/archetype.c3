module ecs::archetype;

import std::collections::map;
import std::collections::bitset;
import std::collections::list;
import std::core::mem::allocator;

import builtin;
import utils::bloom_filter;

import ecs::sparse_list;
import ecs::types;
import ecs::world;
import ecs::archetype_type;

const uint MATCH_BITMASK_SIZE = 1024;
const uint ARCHETYPE_PREALLOCATED_SIZE = 16;

struct TypeInfo {
	usz type_size;
	usz alignment;

	Entity component;
	String name;
}

struct ArchetypeColumn {
	void* data; // pointer to column data array;
	TypeInfo* type_info; // not an array, but a pointer to the type info
}

struct ArchetypeData {
	Entity* entities;
	ArchetypeColumn* columns;

	uint count;
	uint size;
}

alias ArchetypeId = ulong;
alias ArchetypeEdges = HashMap{Id, Archetype*};

struct Archetype {
   	ArchetypeId archetype_id;
	ArchetypeType archetype_type;
	bool alive;

	ArchetypeData data;

	BloomFilter bloom_filter;
	BitSet{MATCH_BITMASK_SIZE} match_bitmask;

	ArchetypeEdges forward_edges;
	ArchetypeEdges backwards_edges;
}

fn void Archetype.generate_matchers(&self) {
	BloomFilter bloom_filter;
	BitSet{MATCH_BITMASK_SIZE} bitmask;

	foreach(component : self.archetype_type.components) {
		if(component > MATCH_BITMASK_SIZE) {
			bloom_filter.add(component);
		} else {
			bitmask.set(component - 1);
		}
	}

	self.bloom_filter = bloom_filter;
	self.match_bitmask = bitmask;
}

fn void Archetype.init(&self, Allocator allocator) {
	uint components_count = (uint)self.archetype_type.components.len();

	if (components_count > 0) {
		Entity* entities = builtin::alloc_list(allocator, Entity, ARCHETYPE_PREALLOCATED_SIZE);
		ArchetypeColumn* columns = builtin::alloc_list(allocator, ArchetypeColumn, components_count);

		// TODO: link with type_info;
		for (int i = 0; i < components_count; i++) {
			uint type_size = 4;

			void* column_data = allocator::malloc(allocator, (ulong)(type_size * ARCHETYPE_PREALLOCATED_SIZE));

			ArchetypeColumn column = {
				.data = column_data,
				.type_info = null,
			};

			columns[i] = column;
		}

		ArchetypeData data = {
			.entities = entities,
			.columns = columns,
			.count = 0,
			.size = ARCHETYPE_PREALLOCATED_SIZE,
		};
		
		self.data = data;
	} else {
		ArchetypeData data = {
			.entities = null,
			.columns = null,
			.count = 0,
			.size = 0,
		};

		self.data = data;
	}
	self.generate_matchers();

	self.forward_edges.init(allocator);
	self.backwards_edges.init(allocator);
}


fn Archetype* archetype_create(World* world, ArchetypeType archetype_type) {
	SparseList{Archetype}* archetype_index = &world.archetype_index;

	Archetype archetype = {
		.archetype_type = archetype_type.clone(world.allocator),
		.alive = false,
	};

	archetype.init(world.allocator);

	Archetype* allocated_archetype = archetype_index.new_element(archetype);
	allocated_archetype.archetype_id = archetype_index.get_latest_alive();

	return allocated_archetype;
}

fn Archetype* archetype_ensure(World* world, ArchetypeType archetype_type) {
	Archetype*? existing_archetype = world.archetypes_map.get_ref(archetype_type);

	if(try existing_archetype) {
		return existing_archetype;
	}

	return archetype_create(world, archetype_type);
}

fn Archetype* archetype_find_with(World* world, Archetype* source, Id id) {
	Archetype*? edge_destination = source.forward_edges[id];

	if(try edge_destination) {
		return edge_destination;
	}

	Archetype* destination;

	@pool() {
		ArchetypeType destination_type = source.archetype_type.clone(tmem, 1);
		destination_type.components.push(id);

		destination = archetype_ensure(world, destination_type);
	};

	source.forward_edges.set(id, destination);
	destination.backwards_edges.set(id, source);	

	return destination;
	
}

fn Archetype* archetype_find_without(World* world, Archetype* source, Id id) {
	Archetype*? edge_destination = *source.backwards_edges.get_ref(id);
	List{Component} source_components = source.archetype_type.components;

	if(try edge_destination) {
		return edge_destination;
	}

	Archetype* destination;

	Allocator temp = tmem;
	@pool() {
		List{Component} destination_components;
		destination_components.init(temp, source_components.len() - 1);

		foreach(component : source_components) {
			if (component != id) {
				destination_components.push(component);
			}
		}

		ArchetypeType destination_type = {
			.components = destination_components,
		};

		destination = archetype_ensure(world, destination_type);
	};

	source.forward_edges.set(id, destination);
	destination.backwards_edges.set(id, source);	

	return destination;
}