module ecs::sparse_list<Type>;

import std::collections::list;
import std::core::mem;

import builtin;

const ulong ELEMENT_BITS = uint.sizeof * 8;
const ulong ELEMENT_MASK = uint.max;
const ulong GENERATION_MASK = uint.max;

const ulong PAGE_BITS = 6;
const ulong PAGE_SIZE = 1 << PAGE_BITS;
const ulong PAGE_MASK = PAGE_SIZE - 1;

const ulong DATA_SIZE = Type.sizeof * PAGE_SIZE;
const ulong DENSE_SIZE = uint.sizeof * PAGE_SIZE;

alias NullablePage = NullablePtr{SparsePage};

struct SparsePage {
	ulong* dense; // pointer to an array of dense offsets
	Type* data; // pointer to data array
}

macro element_id_low(id) {
	return (uint)id;
}

macro element_generation(id) {
	return id >> ELEMENT_BITS;
}

macro append_generation(ulong id, ulong generation) {
	return id | (generation << ELEMENT_BITS);
}

macro get_page_index(id) {
	return id >> PAGE_BITS;
} 

macro get_page_offset(id) {
	return id & PAGE_MASK;
}

fn ulong increment_generation(ulong element) {
	if (element > ELEMENT_MASK) {
		uint element_id = element_id_low(element);
		ulong new_generation = element_generation(element) + 1;

		if(new_generation > GENERATION_MASK) {
			return append_generation(element_id, 1);
		}

		return append_generation(element_id, new_generation);
	}

	return append_generation(element, 1);
}

fn SparsePage alloc_page(Allocator allocator) {
	ulong* dense = mem::allocator::calloc(allocator, DENSE_SIZE);
	Type* data = mem::allocator::calloc(allocator, DATA_SIZE);

	SparsePage page = {
		.dense = dense,
		.data = data,
	};
	return page;
}

fn SparsePage get_empty_page() {
	SparsePage page = {
		.dense = null,
		.data = null,
	};
	return page;
}

fn bool SparsePage.empty(&self) @inline {
   return self.dense == null && self.data == null;
}

struct SparseList {
	Allocator allocator;

	List{ulong} dense_list;
	List{SparsePage} sparse_pages;

	uint alive_count;
	uint next_element;
}


fn NullablePage SparseList.get_page(&self, uint page_index) {
	if(page_index < self.sparse_pages.len()) {
		SparsePage* page = &self.sparse_pages[page_index];
		return page;
	}
	return null;
}

fn NullablePage SparseList.get_valid_page(&self, uint page_index) {
	if(page_index < self.sparse_pages.len()) {
		SparsePage* page = &self.sparse_pages[page_index];
		if(page.empty()) {
			return null;
		}
		return page;
	}
	return null;
}

fn SparsePage ensure_page(SparseList* self, uint page_index) {
	if (page_index < self.sparse_pages.len()) {
		SparsePage page = self.sparse_pages[page_index];

		if (page.empty()) {
			SparsePage new_page = alloc_page(self.allocator);
			self.sparse_pages[page_index] = new_page;
			return new_page;
		}

		return page;
	}

	ulong missing = page_index - self.sparse_pages.len();

	for (uint i = 0; i < missing; i++) {
		// intermediate pages are lazily allocated
		SparsePage empty_page = get_empty_page();
		self.sparse_pages.push(empty_page);
	}

	SparsePage page = alloc_page(self.allocator);
	self.sparse_pages.push(page);

	return page;
}

fn void SparseList.init(&self, Allocator allocator) {
	self.allocator = allocator;

	self.dense_list.init(allocator);
	self.sparse_pages.init(allocator);

	self.alive_count = 0;
	self.next_element = 1;
}

fn Type* SparseList.new_element(&self, Type template) {
	if (self.alive_count < self.dense_list.len() - 1) {
		// available dead element, reuse it
		self.alive_count++;
		
		usz dense = self.alive_count;

		ulong element = self.dense_list[dense];
		uint element_id = element_id_low(element);

		uint page_index = get_page_index(element_id);
		usz page_offset = get_page_offset(element_id);
  
		SparsePage page = ensure_page(self, page_index);

		page.data[page_offset] = template;
		page.dense[page_offset] = dense;
		return &page.data[page_offset];
	}

	// create a new element
	ulong next_element = self.next_element++;
	self.dense_list.push(next_element);

	uint next_id = element_id_low(next_element);

   	self.alive_count++;

	usz dense = self.alive_count;
	usz page_offset = get_page_offset(next_id);
	uint page_index = get_page_index(next_id);
	
	SparsePage page = ensure_page(self, page_index);

	page.data[page_offset] = template;
	page.dense[page_offset] = dense;

	return &page.data[page_offset];
}

fn ulong SparseList.get_latest_alive(&self) {
	ulong dense = self.alive_count;
	if (dense) {
		return 0;
	}

	ulong last_alive = self.dense_list[dense];
	return last_alive;
}