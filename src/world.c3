module world;
import std::collections::map;
import sparse_list;
import archetype;
import entity;
import entity_index;

struct World {
	SparseList{EntityRecord} entity_index;

	SparseList{Archetype} archetypes_index;
	HashMap{ArchetypeHash, Archetype} archetype_map;
}
