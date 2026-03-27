module ecs::archetype;

import std::collections::map;
import std::collections::bitset;
import std::collections::list;
import std::core::mem;
import std::math;

import helpers;
import utils::bloom_filter;

import ecs::sparse_list;
import ecs::types;
import ecs::world;
import ecs::archetype_type;
import ecs::component_index;
import ecs::entity_index;

const uint MATCH_BITMASK_SIZE = 1024;
const uint ARCHETYPE_PREALLOCATED_SIZE = 16;

struct ArchetypeColumn {
	ArrayPtr{void} data; // column data array;
	TypeInfo* type_info; // pointer to the type info
}

struct ArchetypeData {
	ArrayPtr{Entity} entities;
	ArrayPtr{ArchetypeColumn} columns;

	usz columns_count;
	usz count;
	usz capacity;
}

alias ArchetypeId = ulong;
alias ArchetypeEdges = HashMap{Id, Archetype*};

struct Archetype {
	Allocator allocator;
   	ArchetypeId archetype_id;
	ArchetypeType archetype_type;
	bool alive;

	HashMap{Id, ArchetypeColumn*} columns_map;
	HashMap{Id, uint} columns_index;

	ArchetypeData data;

	BloomFilter bloom_filter;
	BitSet{MATCH_BITMASK_SIZE} match_bitmask;

	ArchetypeEdges forward_edges;
	ArchetypeEdges backwards_edges;
}

fn bool Archetype.has_component(Archetype* self, Id id) @inline {
	return self.columns_map.has_key(id);
}

fn ArchetypeColumn*? Archetype.get_column(Archetype* self, Id id) @inline {
	return self.columns_map.get(id);
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
	List{Component} components = self.archetype_type.components;
	uint components_count = (uint)components.len();
	self.allocator = allocator;

	if (components_count > 0) {
		Entity* entities = helpers::talloc(allocator, Entity, ARCHETYPE_PREALLOCATED_SIZE);
		ArchetypeColumn* columns = helpers::talloc(allocator, ArchetypeColumn, components_count);

		// TODO: only allocate columns for components, not tags
		// TODO: link with type_info;

		foreach(index, component : components) {
			uint type_size = 4;
			void* column_data = helpers::malloc(allocator, (usz)(type_size * ARCHETYPE_PREALLOCATED_SIZE), 16)!!;

			ArchetypeColumn column = {
				.data = column_data,
				.type_info = null,
			};

			columns[index] = column;
		}

		ArchetypeData data = {
			.entities = entities,
			.columns = columns,
			.columns_count = components_count,
			.count = 0,
			.capacity = ARCHETYPE_PREALLOCATED_SIZE,
		};
		
		self.data = data;
	} else {
		ArchetypeData data = {
			.entities = null,
			.columns = null,
			.columns_count = 0,
			.count = 0,
			.capacity = 0,
		};

		self.data = data;
	}
	self.generate_matchers();

	self.forward_edges.init(allocator);
	self.backwards_edges.init(allocator);
	
	self.columns_map.init(allocator);
	self.columns_index.init(allocator);
}

fn void Archetype.free_data(&self) {
	helpers::tfree(self.allocator, self.data.entities, Entity);
	self.data.entities = null;

	// freeing columns
	usz columns_count = self.data.columns_count;

	for (int i = 0; i < columns_count; i++) {
		ArchetypeColumn* column = &self.data.columns[i];
		if (column.data == null) continue;

		helpers::mfree(self.allocator, column.data, column.type_info.alignment);
		column.data = null;
	}

	helpers::tfree(self.allocator, self.data.columns, ArchetypeColumn);
	self.data.columns = null;
}

fn void Archetype.free(&self) {	
	self.archetype_type.free();

	self.forward_edges.free();
	self.backwards_edges.free();

	self.columns_map.free();
	self.columns_index.free();

	self.free_data();
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
	@pool() {
		List{Component} destination_components;
		destination_components.init(tmem, source_components.len() - 1);

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


fn void archetype_ensure_capacity(Allocator allocator, ArchetypeData* data, usz new_count) {
	if (data.capacity >= new_count) return;

	assert(new_count < usz.max / 2);
	usz new_capacity = data.capacity > 0 ? data.capacity * 2 : ARCHETYPE_PREALLOCATED_SIZE;

	while (new_capacity < new_count) {
		new_capacity *= 2;
	}

	new_capacity = math::next_power_of_2(new_capacity);
	data.entities = helpers::trealloc(allocator, data.entities, Entity, new_capacity);

	for (int i = 0; i < data.columns_count; i++) {
		ArchetypeColumn* column = &data.columns[i];
		if (column.data == null) continue;

		TypeInfo type_info = *column.type_info;
		column.data = helpers::mrealloc(allocator, column.data, type_info.type_size * new_capacity, type_info.alignment)!!;
	}

	data.capacity = new_capacity;
}


fn void archetype_insert_entity(Archetype* archetype, Entity entity, EntityRecord* record) {
	usz assign_row = archetype.data.count++;
	archetype_ensure_capacity(archetype.allocator, &archetype.data, assign_row);
	
	archetype.data.entities[assign_row] = entity;

	if(assign_row == 0) {
		// archetype was empty, marking as alive
		archetype.alive = true;
	}

	record.archetype = archetype;
	record.archetype_row = assign_row;
}

fn void archetype_move_entity(World* world, Archetype* source, Archetype* destination, Entity entity, EntityRecord* record) {
	usz source_row = record.archetype_row;
	usz source_last_row = source.data.count - 1;
	usz assigned_row = destination.data.count;

	archetype_ensure_capacity(world.allocator, &destination.data, assigned_row);

	if (source_row != source_last_row) {
		Entity swapped_entity = source.data.entities[source_last_row];
		source.data.entities[source_row] = swapped_entity;
 
		EntityRecord* swapped_record = world.entity_index.entity_record_get(swapped_entity)!!;
		swapped_record.archetype_row = source_row;

		foreach (index, component : source.archetype_type.components) {
			ArchetypeColumn* source_column = &source.data.columns[index];
			if (source_column.data == null) continue;

			usz type_size = source_column.type_info.type_size;
			char* source_data = (char*)source_column.data;

			ArchetypeColumn*? destination_column = destination.columns_map.get(component);
			if (try destination_column) {
				if (destination_column.data == null) continue;
				char* destination_data = (char*)destination_column.data;

				mem::copy(
					&destination_data[assigned_row * type_size], 
					&source_data[source_row * type_size], 
					type_size
				);
			}

			// swaping columns
			mem::copy(
				&source_data[source_row * type_size], 
				&source_data[source_last_row * type_size], 
				type_size
			);
		};

	} else {
		// moving last column row to destination columns;
		foreach (index, component : source.archetype_type.components) {
			ArchetypeColumn* source_column = &source.data.columns[index];
			if (source_column.data == null) continue;

			ArchetypeColumn*? destination_column = destination.columns_map.get(component);

			if (try destination_column) {
				if (destination_column.data == null) continue;

				usz type_size = source_column.type_info.type_size;
				
				char* source_data = (char*)source_column.data;
				char* destination_data = (char*)destination_column.data;

				mem::copy(
					&destination_data[assigned_row * type_size], 
					&source_data[source_row * type_size], 
					type_size
				);
			}
		};
	}

	destination.data.count++;
	source.data.count--;

	record.archetype = destination;
	record.archetype_row = assigned_row;
}

fn void archetype_modify_column(ArchetypeColumn* column, usz row, void* data) {
	usz type_size = column.type_info.type_size;
	char* column_data = (char*)column.data;

	mem::copy(
		&column_data[row * type_size],
		data,
		type_size
	);
}