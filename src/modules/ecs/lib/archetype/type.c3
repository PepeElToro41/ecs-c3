module ecs::archetype_type;

import std::core::mem::allocator;
import std::collections::list;

import ecs::types;

struct ArchetypeType {
	uint cached_hash;
    bool cached;
	List{Component} components;
}

fn uint ArchetypeType.hash(&self) {
	if (self.cached) {
		return self.cached_hash;
	}
	ulong cached_hash = 2166136261u;

	foreach(component : self.components) {
		cached_hash ^= component;
		cached_hash *= 16777619u;
	}

	self.cached_hash = (uint)cached_hash;
	self.cached = true;
	return (uint)cached_hash;
}

fn bool ArchetypeType.equals(&self, ArchetypeType other) @operator(==) {
	foreach (index, component : self.components) {
		if (component != other.components[index]) {
			return false;
		}
	}

	return true;
}

fn void ArchetypeType.free(&self) {
	self.components.free();
}

fn ArchetypeType ArchetypeType.clone(&self, Allocator allocator, uint reserve = 0) {
	List{Component} cloned_components;
	cloned_components.init(allocator, self.components.len() + reserve);

	foreach(component : self.components) {
		cloned_components.push(component);
	}

	ArchetypeType cloned = {
		.components = cloned_components,
		.cached = false,
		.cached_hash = 0,
	};

	return cloned;	
}

fn ArchetypeType create_empty(Allocator allocator) {
	List{Component} components;
	components.init(allocator, 1);

	return {
		.components = components,
		.cached = false,
		.cached_hash = 0,
	};
}