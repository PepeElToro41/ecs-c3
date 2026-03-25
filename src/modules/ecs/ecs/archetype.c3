module ecs::archetype;

import std::collections::list;
import std::collections::bitset;

import utils::bloom_filter;
import ecs::entity;

const short MATCH_BITMASK_SIZE = 1024; 

struct ArchetypeHash {
	uint cached_hash;
    bool cached;
	uint *components_list;
	int components_count;
}

fn uint ArchetypeHash.hash(&self) {
	if (self.cached) {
		return self.cached_hash;
	}
	uint cached_hash = 2166136261u;

	for (int i = 0; i < self.components_count; i++) {
		uint component = self.components_list[i];
		cached_hash ^= component;
		cached_hash *= 16777619u;
	}
	self.cached_hash = cached_hash;
	self.cached = true;

	return cached_hash;
}

fn bool ArchetypeHash.equals(&self, ArchetypeHash other) @operator(==) {
	for (int i = 0; i < self.components_count; i++) {
		if (self.components_list[i] != other.components_list[i]) {
			return false;
		}
	}

	return true;
}

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

struct Archetype {
   	ulong archetype_id;
	ArchetypeHash hash;
	bool alive;

	Component* components;
	uint components_count;

	ArchetypeData data;

	BloomFilter bloom_filter;
	bitset::BitSet{MATCH_BITMASK_SIZE} match_bitmask;
}