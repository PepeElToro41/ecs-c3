import std::collections::list;
import std::collections::range;
import archetype;

alias Entity = ulong;
alias EntityId = uint;

const ulong ENTITY_BITS = uint.sizeof * 8;
const ulong ENTITY_MASK = uint.max;
const ulong GENERATION_MASK = uint.max;
const uint ENTITY_PAGE_BITS = 10;
const uint ENTITY_PAGE_SIZE = 1 << ENTITY_PAGE_BITS;
const uint ENTITY_PAGE_MASK = ENTITY_PAGE_SIZE - 1;

struct EntityRecord {
	Archetype* archetype;
	usz archetype_row;
	usz dense;
}

struct EntityPage {
	EntityRecord[ENTITY_PAGE_SIZE]* records;
}

macro entity_id_low(id) {
	return id & ENTITY_MASK;
}

macro entity_generation(id) {
	return id >> ENTITY_BITS;
}

macro append_generation(ulong id, ulong generation) {
	return id | (generation << ENTITY_BITS);
}

macro get_page_index(id) {
	return id >> ENTITY_PAGE_BITS;
}

macro get_page_offset(id) {
	return id & ENTITY_PAGE_MASK;
}

fn Entity increment_generation(Entity id) {
	if (id > ENTITY_MASK) {
		Entity entity_id = entity_id_low(id);
		Entity new_generation = entity_generation(id) + 1;

		if(new_generation > GENERATION_MASK) {
			return append_generation(entity_id, 1);
		}

		return append_generation(entity_id, new_generation);
	}

	return append_generation(id, 1);
}

fn EntityPage alloc_page(Allocator allocator) {
	EntityRecord[ENTITY_PAGE_SIZE]* records = allocator::calloc(allocator, EntityRecord.sizeof * ENTITY_PAGE_SIZE);

	EntityPage page;
	page.records = records;
	return page; 
}

fn EntityPage get_empty_page() {
	EntityPage page = {};
	page.records = null;
	return page;
}

fn bool EntityPage.empty(&self) @inline {
	return self.records == null;
}

struct EntityIndex {
	Allocator allocator;

	List{EntityPage} sparse_pages;
	List{Entity} dense_list;

	Range{uint} entity_range;
	bool use_range;

	uint alive_count;
	uint entity_count;
}

fn EntityPage* get_page(EntityIndex* self, uint page_index) {
	if (page_index < self.sparse_pages.len()) {
		EntityPage *page = &self.sparse_pages[page_index];
    	if (page.empty()) {
        	return null;
    	}

		return page; 
	}

	return null;
}
 
fn EntityPage ensure_page(EntityIndex* self, uint page_index) {
	if (page_index < self.sparse_pages.len()) {
		EntityPage page = self.sparse_pages[page_index];

		if (page.empty()) {
			EntityPage new_page = alloc_page(self.allocator);
			self.sparse_pages[page_index] = new_page;
			return new_page;
		}

		return page;
	}

	ulong missing = page_index - self.sparse_pages.len();

	for (uint i = 0; i < missing; i++) {
		// intermediate pages are lazily allocated
		EntityPage empty_page = get_empty_page();
		self.sparse_pages.push(empty_page);
	}

	EntityPage page = alloc_page(self.allocator);
	self.sparse_pages.push(page);

	return page;
}


fn void dense_swap_recycle(EntityIndex* self, Entity entity, EntityRecord* record) {
	usz dense = record.dense;
	usz alive_count = self.alive_count;

	Entity last_alive = self.dense_list[alive_count];

	if(entity != last_alive) {
		self.dense_list[dense] = last_alive;
		self.dense_list[alive_count] = increment_generation(entity);

		record.dense = alive_count;
		EntityRecord* swapped_record = self.get_entity_record(last_alive);
		swapped_record.dense = dense;
	}
	self.alive_count--;
}

fn void dense_swap_delete(EntityIndex* self, Entity entity, EntityRecord* record) {
	usz dense = record.dense;
	Entity last_alive = self.dense_list[self.alive_count];
	Entity? last = self.dense_list.pop();

	if(catch last) unreachable("entity dense list is empty");

	if(entity != last_alive) {
		self.dense_list[dense] = last_alive;

		EntityRecord* swapped_record = self.get_entity_record(last_alive);
		swapped_record.dense = dense;
	}

	self.dense_list[self.alive_count] = last;
	EntityRecord* last_record = self.get_entity_record(last);
	last_record.dense = self.alive_count;
	
	record.dense = 0;
	self.alive_count--;
}

fn EntityRecord* EntityIndex.get_entity_record(&self, Entity id) {
	EntityId entity_id = (uint)entity_id_low(id);
	uint page_index = get_page_index(entity_id);

	EntityPage* page = get_page(self, page_index);
	if (!page) {
		return null;
	}

	usz page_offset = get_page_offset(entity_id);
	EntityRecord* record = &page.records.[page_offset];
	return record;
} 

fn void EntityIndex.init(&self, Allocator allocator) {
	self.allocator = allocator;
	self.dense_list.init(allocator);

	// sparse arrays will point to zero when the id doesn't exist
	self.dense_list.push(0);
}

fn Entity EntityIndex.new_entity(&self) {
	defer self.alive_count++;

	if (self.alive_count < self.dense_list.len() - 1) {
		// available dead entity, reuse it
		self.alive_count++;
		return self.dense_list[self.alive_count];
	}

	// create a new entity
	Entity new_id = self.entity_count++;
	self.dense_list.push(new_id);
	return new_id;
}


fn void EntityIndex.make_alive(&self, Entity id) {

}

fn void EntityIndex.set_range(&self, uint min, uint max) {
	Range{uint} range = { min, max };
	self.entity_range = range;
	self.use_range = true;
}


fn void EntityIndex.delete_entity(&self, Entity id, EntityRecord* record) {
	EntityId entity_id = (uint)entity_id_low(id);
	usz dense_index = record.dense;
	if (dense_index == 0) {
		return;
	}

	if (self.use_range && !self.entity_range.contains(entity_id) ) {
		// entity is not in range, do not reuse
		dense_swap_delete(self, id, record);
	} else {
		dense_swap_recycle(self, id, record);
	}
}