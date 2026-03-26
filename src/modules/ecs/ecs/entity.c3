module ecs::entity;

import ecs::archetype;
import ecs::entity_index;
import ecs::world;
import ecs::types;

fn Entity create_new_id(World* world) {
	Entity new_entity = world.entity_index.new_entity()!!;
	EntityRecord* record = world.entity_index.entity_record_ensure(new_entity);

	record.archetype = world.root_archetype;
	record.archetype_row = 0;
	return new_entity;
}