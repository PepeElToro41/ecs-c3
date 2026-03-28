module ecs::component_index;

import std::collections::map;
import std::core::mem::allocator;

import ecs::archetype;
import ecs::types;
import ecs::world;
import ecs::entity;
import ecs::sparse_list;

const ulong FLAG_IS_PAIR            = 1 << 0;
const ulong FLAG_IS_EXCLUSIVE       = 1 << 1;
const ulong FLAG_HAS_DELETE         = 1 << 2;
const ulong FLAG_IS_COMPONENT       = 1 << 3;
const ulong FLAG_IS_TGT_WILDCARD    = 1 << 4;
const ulong FLAG_IS_REL_WILDCARD    = 1 << 5;

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
   ulong sparse_id;

	uint archetype_count;
   TypeInfo* type_info;
	BitFlags flags;
	PairRecord pair_record;
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


fn TypeInfo* get_component_type_info(World* world, Id relation, Id target) {
	if (target && entity::entity_has_id(world, relation, world::ECS_FORCE_TAG)) {
		return null;
	}

	bool is_component = entity::entity_has_id(world, relation, world::ECS_COMPONENT);
	
   if(is_component) {
      return world.component_infos.get_ref(relation) ?? null;
   } else {
      bool target_is_component = entity::entity_has_id(world, target, world::ECS_COMPONENT);

      if (target && target_is_component) {
         return world.component_infos.get_ref(target) ?? null;
      }
   }

	return null;
}

fn ComponentRecord* component_record_create(World* world, Component id) {
   bool is_pair = entity::is_pair(id);
	bool is_exclusive = false;
   bool is_traversable = false;
	bool has_delete = false;

	Entity relation = id;
	Entity target = 0;

	ComponentRecord record = {
		.archetype_count = 0,
		.flags = 0,
	};
	
	if(is_pair) {
      Pair relation_id = entity::pair_first(id);
      Pair target_id = entity::pair_second(id);

		relation = world.entity_index.entity_get_alive(relation_id)!!;
		target = world.entity_index.entity_get_alive(target_id)!!;

      is_exclusive = entity::entity_has_id(world, relation, world::ECS_EXCLUSIVE);
   }

	TypeInfo* type_info = get_component_type_info(world, relation, target);
   bool is_component = type_info != null;

	record.flags = 0 
		| (is_pair ? FLAG_IS_PAIR : 0)
		| (is_exclusive ? FLAG_IS_EXCLUSIVE : 0)
		| (has_delete ? FLAG_HAS_DELETE : 0)
		| (is_component ? FLAG_IS_COMPONENT : 0);

	record.init(world.allocator);

   SparseList{ComponentRecord}* component_index = &world.component_index;

   ComponentRecord* allocated_record = component_index.new_element(record);
   allocated_record.sparse_id = component_index.get_latest_alive();

   if (is_pair) {
      Pair relation_wildcard = entity::ecs_pair(relation, world::ECS_WILDCARD);
      Pair target_wildcard = entity::ecs_pair(world::ECS_WILDCARD, target);

      if (relation_wildcard == id) {
         allocated_record.flags |= FLAG_IS_REL_WILDCARD;
      } else if (target_wildcard == id) {
         allocated_record.flags |= FLAG_IS_TGT_WILDCARD;
      } else {
         ComponentRecord* relation_record = component_record_ensure(world, relation_wildcard);
         ComponentRecord* target_record = component_record_ensure(world, target_wildcard);

         relation_record.pair_record.first_records.set(id, allocated_record);
         target_record.pair_record.second_records.set(id, allocated_record);

         if (relation_record.flags & FLAG_IS_TRAVERSABLE) {
            target_record.pair_record.trav_records.set(id, allocated_record);
         }
      }
   }

	return allocated_record;
}

fn ComponentRecord* component_record_ensure(World* world, Component component) {
	ComponentRecord*? record = world.components_map.get(component);
	if (try record) {
		return record;
	}
	return component_record_create(world, component);
}