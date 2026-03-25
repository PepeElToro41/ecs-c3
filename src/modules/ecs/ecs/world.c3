module ecs::world;
import std::collections::map;
import sparse_list;
import ecs::archetype;
import ecs::entity;
import ecs::entity_index;

struct World {
	EntityIndex entity_index;
	SparseList{Archetype} archetypes_index;

	HashMap{ArchetypeHash, Archetype} archetypes_map;
}
