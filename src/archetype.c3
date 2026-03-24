module archetype;

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

struct Archetype {
   int archetype_id;
   ArchetypeHash hash;
}