module ecs::entity_index;

import std::collections::list;
import std::collections::range;
import std::core::mem;
import std::math;
import std::io;

import ecs::entity;
import ecs::archetype;

const ulong ENTITY_BITS = uint.sizeof * 8;
const ulong ENTITY_MASK = uint.max;
const ulong GENERATION_MASK = uint.max;

const uint ENTITY_PAGE_BITS = 10;
const uint ENTITY_PAGE_SIZE = 1 << ENTITY_PAGE_BITS;
const uint ENTITY_PAGE_MASK = ENTITY_PAGE_SIZE - 1;

struct EntityRecord {
	Archetype* archetype;
	ulong archetype_row;
	ulong dense;
}

struct EntityPage {
	EntityRecord[ENTITY_PAGE_SIZE]* records;
}

struct EntityIndex {
	Allocator allocator;

	List{EntityPage} sparse_pages;
	List{Entity} dense_list;

	Range{uint} entity_range;
	bool use_range;

	uint alive_count;
	uint next_entity;
}

macro entity_id_low(id) {
	return (uint)id;
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
		EntityId entity_id = entity_id_low(id);
		Entity new_generation = entity_generation(id) + 1;

		if(new_generation > GENERATION_MASK) {
			return append_generation(entity_id, 1);
		}

		return append_generation(entity_id, new_generation);
	}

	return append_generation(id, 1);
}

fn EntityPage alloc_page(Allocator allocator) {
	EntityRecord[ENTITY_PAGE_SIZE]* records = mem::allocator::calloc(allocator, EntityRecord.sizeof * ENTITY_PAGE_SIZE);

	EntityPage page = {
		.records = records,
	};
	return page; 
}

fn EntityPage get_empty_page() {
	EntityPage page = {
		.records = null,
	};
	return page;
}

fn bool EntityPage.empty(&self) @inline {
	return self.records == null;
}

fn void free_page(EntityPage* self, Allocator allocator) {
   mem::allocator::free(allocator, self.records);
}

fn EntityPage* get_page(EntityIndex* self, uint page_index) {
	if (page_index < self.sparse_pages.len()) {
		EntityPage *page = &self.sparse_pages[page_index];
		return page; 
	}
	return null;
}

fn EntityPage* get_valid_page(EntityIndex* self, uint page_index) {
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
		EntityRecord* swapped_record = self.entity_record_get(last_alive);
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
   
		EntityRecord* swapped_record = self.entity_record_ensure(last_alive);
		swapped_record.dense = dense;
	}

   
   	if (last != last_alive) {
      	self.dense_list[self.alive_count] = last;
      	EntityRecord* last_record = self.entity_record_ensure(last);
      	last_record.dense = self.alive_count;
   	}
	
	record.dense = 0;
	self.alive_count--;
}

fn EntityRecord* EntityIndex.entity_record_get(&self, Entity entity) {
	EntityId entity_id = entity_id_low(entity);
	uint page_index = get_page_index(entity_id);

	EntityPage* page = get_valid_page(self, page_index);
	if (!page) {
		return null;
	}

	usz page_offset = get_page_offset(entity_id);
	EntityRecord* record = &page.records.[page_offset];
	return record;
}

fn EntityRecord* EntityIndex.entity_record_ensure(&self, Entity entity) {
	EntityId entity_id = entity_id_low(entity);
	uint page_index = get_page_index(entity_id);
	usz page_offset = get_page_offset(entity_id);

	EntityPage page = ensure_page(self, page_index);
	EntityRecord* record = &page.records.[page_offset];
	return record;
}

fn void EntityIndex.init(&self, Allocator allocator) {
	self.allocator = allocator;
	self.dense_list.init(allocator);
	self.next_entity = 1;
	self.alive_count = 0;
	self.use_range = false;

	// sparse arrays will point to zero when the id doesn't exist
	// this means that dense array is one-indexed (lesgoooo :D)
	self.dense_list.push(0);
}

faultdef ENTITY_OUT_OF_RANGE;

fn Entity? EntityIndex.new_entity(&self) {
	if (self.alive_count < self.dense_list.len() - 1) {
		// available dead entity, reuse it
		self.alive_count++;
		return self.dense_list[self.alive_count];
	}

	// create a new entity
	Entity next_entity = self.next_entity++;
	self.dense_list.push(next_entity);

	if (self.use_range) {
		bool in_range = self.entity_range.contains(entity_id_low(next_entity));

      	if (!in_range) {
         	return ENTITY_OUT_OF_RANGE~;
      	}
	}

	EntityId next_id = entity_id_low(next_entity);

	self.alive_count++;
	usz dense = self.alive_count;

	EntityRecord new_record = {
		.archetype = null,
		.archetype_row = 0,
		.dense = dense,
	};
	
	EntityPage page = ensure_page(self, get_page_index(next_id));
	usz page_offset = get_page_offset(next_id);
	
	page.records.[page_offset] = new_record;
	return next_id;
}


fn void EntityIndex.make_alive(&self, Entity entity) {
	EntityRecord* record = self.entity_record_ensure(entity);
	usz dense = record.dense;

	if (dense != 0) {
		if (dense <= self.alive_count) {
			// entity is already alive
			// overwriting generation
			self.dense_list[dense] = entity;
			return;
		}
		
    	self.alive_count++;
		usz dead_dense = self.alive_count;
		if (dense == dead_dense) {
			// entity is the next one to be alive
			// incrementing alive count makes it alive
			// overwriting generation
			self.dense_list[dense] = entity;
			return;
		}

		// swapping with the first dead entity
		Entity first_dead = self.dense_list[dead_dense];

		self.dense_list[dense] = first_dead;
		self.dense_list[dead_dense] = entity;

		EntityRecord* dead_record = self.entity_record_ensure(first_dead);
		dead_record.dense = dense;
		record.dense = dead_dense;
	} else {
		if (self.alive_count == self.dense_list.len() - 1) {
			// no more dead entities, pushing the new entity
			self.dense_list.push(entity);
			self.alive_count++;
			usz dead_dense = self.alive_count;
			record.dense = dead_dense;
		} else {
			// pushing first dead entity at the end, and replacing it with the new entity
			self.alive_count++;
			usz dead_dense = self.alive_count;
			Entity first_dead = self.dense_list[dead_dense];

			self.dense_list.push(first_dead);
			self.dense_list[dead_dense] = entity;

			EntityRecord* dead_record = self.entity_record_ensure(first_dead);
			dead_record.dense = self.dense_list.len() - 1;
			record.dense = dead_dense;
		}
	}
}

fn void EntityIndex.set_range(&self, uint range_min, uint range_max) {
	Range{uint} range = { range_min, range_max };
	self.entity_range = range;
	self.use_range = true;


	self.next_entity = max(self.next_entity, range_min);
}

fn void EntityIndex.free(&self) {
	self.dense_list.free();

   	foreach (page : self.sparse_pages) {
    	free_page(&page, self.allocator);
   	}

	self.sparse_pages.free();
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
