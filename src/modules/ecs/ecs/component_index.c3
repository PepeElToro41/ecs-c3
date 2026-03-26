module ecs::component_index;

import std::collections::map;
import ecs::archetype;
import ecs::types;

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
	HashMap{ArchetypeId, uint} column_index;

	uint archetype_count;
	ulong flags;

	PairRecord* pair_record; // data about pairs, null for non-pairs
}