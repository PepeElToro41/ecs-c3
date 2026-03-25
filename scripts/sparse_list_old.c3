module sparse_list_old<Type>;
import std::collections::list;
import std::core::mem::allocator;

struct SparsePage {
	uint* dense_index; // pointer to dense array
	Type* data; // pointer to array data
}


fn SparsePage alloc_page(Allocator allocator, uint page_size) {
	uint* dense_index = allocator::calloc(allocator, page_size * uint.sizeof);
	Type* data = allocator::calloc(allocator, page_size * Type.sizeof);

	SparsePage page;
	page.dense_index = dense_index;
	page.data = data;

	return page;
}

fn SparsePage get_empty_page() {
   SparsePage page;
   page.dense_index = null;
   page.data = null;
   return page;
}

fn bool SparsePage.empty(&self) @inline {
   return self.dense_index == null && self.data == null;
}

struct SparseList {
	Allocator allocator;

	List{ulong} dense_list;
	List{SparsePage} sparse_pages;

	uint alive_count;	
	uint id_count;

	uint page_bits;
	uint page_size;
}

macro get_page_index(id, page_bits) {
	return id >> page_bits;
}

macro get_page_size(page_bits) {
	return 1 << page_bits;
}

macro get_page_offset(sparse_offset, page_size) {
   return (long)(sparse_offset % page_size);
} 

fn SparsePage* SparseList.page_get(&self, uint page_index) {
	if (page_index < self.sparse_pages.len()) {
		SparsePage *page = &self.sparse_pages[page_index];
    	if (page.empty()) {
        	return null;
    	}

		return page; 
	}
   
	return null;
}

fn SparsePage SparseList.page_ensure(&self, uint page_index) {
	if (page_index < self.sparse_pages.len()) {
		SparsePage page = self.sparse_pages[page_index];

		if (page.empty()) {
			SparsePage new_page = alloc_page(self.allocator, self.page_size);
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

	SparsePage page = alloc_page(self.allocator, self.page_size);
	self.sparse_pages.push(page);

	return page;
}

fn void SparseList.init(&self, Allocator allocator, uint page_bits = 6) {
	self.page_bits = page_bits;
	self.page_size = get_page_size(page_bits);

	self.allocator = allocator;
	self.dense_list.init(allocator);
	self.sparse_pages.init(allocator);

	// sparse arrays will point to zero when the id doesn't exist
	self.dense_list.push(0);
}

fn void SparseList.free(&self) {
	foreach (page : self.sparse_pages) {
		allocator::free(self.allocator, page.dense_index);
		allocator::free(self.allocator, page.data);
	}

	self.dense_list.free();
	self.sparse_pages.free();
}

fn SparsePage* SparseList.get_valid_page(&self, uint sparse_id) @inline  {
	uint page_index = get_page_index(sparse_id, self.page_bits);
	SparsePage* page = self.page_get(page_index);

	return page;
}

fn Type* SparseList.get_any(&self, ulong id) {
	uint sparse_id = (uint)id;
	if (sparse_id == 0) return null;
	
	uint sparse_offset = sparse_id - 1;
	SparsePage* page = self.get_valid_page(sparse_offset);

	if (!page) {
		return null;
	}

	usz page_offset = get_page_offset(sparse_offset, self.page_size);
	Type* data_ref = page.data + page_offset;
 
	return data_ref;
}

fn bool SparseList.contains(&self, ulong id) {
	uint sparse_id = (uint)id;
	if (sparse_id == 0) return false;

	uint sparse_offset = sparse_id - 1;
	SparsePage* page = self.get_valid_page(sparse_offset);

	if (!page) {
		return false;
	}

	usz page_offset = get_page_offset(sparse_offset, self.page_size);
	uint dense_index = page.dense_index[page_offset];

	if (dense_index == 0) {
		return false;
	}
	if(dense_index > self.alive_count) {
    	return false;
	}

	return self.dense_list[dense_index] == id;
}

fn ulong SparseList.get_full_id(&self, uint sparse_id) {
	if(sparse_id == 0) return 0;
	uint sparse_offset = sparse_id - 1;

	SparsePage* page = self.get_valid_page(sparse_offset);
	usz page_offset = get_page_offset(sparse_offset, self.page_size);
	uint dense_index = page.dense_index[page_offset];

	return self.dense_list[dense_index];
}


fn void SparseList.create_id(&self) {

}

fn void SparseList.delete_id(&self, ulong id) {}