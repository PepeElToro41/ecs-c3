module ecs::component_index;

import std::collections::map;
import std::core::mem::allocator;

import ecs::archetype;
import ecs::types;
import ecs::world;
import ecs::entity;


const ulong FLAG_IS_PAIR = 1;
const ulong FLAG_IS_EXCLUSIVE = 1 << 1;
const ulong FLAG_HAS_DELETE = 1 << 2;
const ulong FLAG_IS_COMPONENT = 1 << 3;


struct PairRecord {
 	HashMap{ArchetypeId, uint} pairs_count;

	// all pairs with (R, *)
	HashMap{Pair, ComponentRecord*} first_records;
	// all pairs with (*, T)
	HashMap{Pair, ComponentRecord*} second_records;
	// all pairs with (R, T) where R has Traversable trait
	HashMap{Pair, ComponentRecord*} trav_records;
}

struct ComponentRecord {
	HashMap{ArchetypeId, uint} columns_index;

	uint archetype_count;
	BitFlags flags;

	PairRecord pair_record; // data about pairs, null for non-pairs
}

fn void PairRecord.init(&self, Allocator allocator) {
	self.pairs_count.init(allocator);
	self.first_records.init(allocator);
	self.second_records.init(allocator);
	self.trav_records.init(allocator);
}

fn void PairRecord.free(&self) {
	self.pairs_count.free();
	self.first_records.free();
	self.second_records.free();
	self.trav_records.free();
}

fn void ComponentRecord.init(&self, Allocator allocator) {
	self.columns_index.init(allocator);

	if(self.flags & FLAG_IS_PAIR) {
		self.pair_record.init(allocator);
	}
}


fn void ComponentRecord.free(&self) {
	if(self.flags & FLAG_IS_PAIR) {
		self.pair_record.free();
	}

	self.columns_index.free();
}


fn bool check_is_component(World* world, Id relation, Id target) {
	if (target && entity::entity_has_id(world, relation, world::ECS_FORCE_TAG)) {
		return false;
	}

	bool is_component = entity::entity_has_id(world, relation, world::ECS_COMPONENT);
	if (target && !is_component) {
		return entity::entity_has_id(world, target, world::ECS_COMPONENT);
	}

	return is_component;
}

fn ComponentRecord* component_record_create(World* world, Component component) {
	bool is_pair = entity::is_pair(component);
	bool is_exclusive = false;
	bool has_delete = false;
	Entity relation = component;
	Entity target = 0;

	ComponentRecord* record = allocator::new(world.allocator, ComponentRecord, {
		.columns_index = HashMap{ArchetypeId, uint},
		.archetype_count = 0,
		.flags = 0,
		.pair_record = null,
	});
	
	if(is_pair) {
		relation = entity_index::get_entity_alive(entity::pair_first(component))!!;
		target = entity_index::get_entity_alive(entity::pair_second(component))!!;
	
		record.pair_record = {
			.pairs_count = HashMap{Pair, ComponentRecord*},
			.first_records = HashMap{Pair, ComponentRecord*},
			.second_records = HashMap{Pair, ComponentRecord*},
			.trav_records = HashMap{Pair, ComponentRecord*},
		};
	}

	bool is_component = check_is_component(world, relation, target);

	record.flags = 0 
		| (is_pair ? FLAG_IS_PAIR : 0)
		| (is_exclusive ? FLAG_IS_EXCLUSIVE : 0)
		| (has_delete ? FLAG_HAS_DELETE : 0)
		| (is_component ? FLAG_IS_COMPONENT : 0);

	record.init();
	return record;
}

fn ComponentRecord* component_record_ensure(World* world, Component component) {
	ComponentRecord*? record = world.component_index.get(component);
	if (try record) {
		return record;
	}
	return component_record_create(world, component);
}