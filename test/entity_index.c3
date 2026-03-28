module ecs_test;
import std::core::test;
import std::io;

import ecs::entity_index;
import ecs::types;

fn void create_new_entity() @test {
	EntityIndex index;
	index.init(mem);
	defer index.free();

	test::eq(index.new_entity()!!, 1);
	test::eq(index.new_entity()!!, 2);
	test::eq(index.new_entity()!!, 3);
	test::eq(index.new_entity()!!, 4);

	test::eq(index.next_entity, 5);
	test::eq(index.alive_count, 4);

	test::@check(@ok(entity_index::get_page(&index, 0)));
	// second page shouldnt be allocated
	test::@check(!@ok(entity_index::get_page(&index, 1)));
}

fn void entity_record() @test {
	EntityIndex index;
	index.init(mem);
	defer index.free();

	Entity entity1 = index.new_entity()!!;
	Entity entity2 = index.new_entity()!!;

	EntityRecord* record1 = index.entity_record_get(entity1)!!;
	EntityRecord* record2 = index.entity_record_get(entity2)!!;

	test::eq(record1.dense, 1);
	test::eq(record2.dense, 2);
}

fn void entity_recycling() @test {
	EntityIndex index;
	index.init(mem);
	defer index.free();

	index.new_entity()!!;
	index.new_entity()!!;
	index.new_entity()!!;
	index.new_entity()!!;

	EntityRecord* deleted_record = index.entity_record_get(2)!!;
	index.delete_entity(2, deleted_record);

	test::eq(index.next_entity, 5);
	test::eq(index.alive_count, 3);

	Entity reused_entity = index.new_entity()!!;
	EntityRecord* reused_record = index.entity_record_get(reused_entity)!!;

	test::eq(entity_index::entity_id_low(reused_entity), 2);
	test::eq(entity_index::entity_generation(reused_entity), 1);
	test::eq(reused_entity, entity_index::append_generation(2, 1));

	test::eq(deleted_record, reused_record);
}

fn void entity_make_alive() @test {
	EntityIndex index;
	index.init(mem);
	defer index.free();

	index.new_entity()!!;
	index.new_entity()!!;
	index.new_entity()!!;
	index.new_entity()!!;

	index.make_alive(entity_index::ENTITY_PAGE_SIZE * 3);

	EntityPage page0 = entity_index::get_page(&index, 0)!!;
	EntityPage page1 = entity_index::get_page(&index, 1)!!;
	EntityPage page2 = entity_index::get_page(&index, 2)!!;
	EntityPage page3 = entity_index::get_page(&index, 3)!!;
	EntityPage? page4 = entity_index::get_page(&index, 4);

	test::@check(!page0.empty(), "page0 is empty");
	test::@check(page1.empty(), "page1 should be lazily allocated");
	test::@check(page2.empty(), "page2 should be lazily allocated");
	test::@check(!page3.empty(), "page3 is empty");
	test::@check(!@ok(page4), "page4 should not be created");

	index.make_alive(entity_index::ENTITY_PAGE_SIZE * 2);
	
	page1 = entity_index::get_page(&index, 1)!!;
	page2 = entity_index::get_page(&index, 2)!!;

	test::@check(page1.empty(), "page1 should be lazily allocated");
	test::@check(!page2.empty(), "page2 should be allocated when empty");
}

fn void entity_range_creation() @test {
	EntityIndex index;
	index.init(mem);
	defer index.free();

	index.set_range(10, 20);

	Entity entity1 = index.new_entity()!!;

	test::eq(entity1, 10);

	for (int i = 0; i < 10; i++) {
		Entity entity = index.new_entity()!!;
	}

	Entity? failed_entity = index.new_entity();
	test::@check(!@ok(failed_entity), "entity should error when out of range");
}

fn void entity_outside_range_deletion() @test {
	// should not recycle entities outside of range

	EntityIndex index;
	index.init(mem);
	defer index.free();

	index.set_range(10, 20);

	index.make_alive(21);
	index.make_alive(22);
	index.make_alive(23);

	index.delete_entity(21, index.entity_record_get(21)!!);
	index.delete_entity(22, index.entity_record_get(22)!!);
	index.delete_entity(23, index.entity_record_get(23)!!);

	test::eq(index.dense_list.len(), 1);
	test::eq(index.new_entity()!!, 10);
	test::eq(index.new_entity()!!, 11);
	test::eq(index.new_entity()!!, 12);
}
