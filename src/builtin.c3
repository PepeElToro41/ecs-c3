module builtin;
import std::core::mem::allocator;

alias NullablePtr<Type> = Type*;


macro alloc_list(Allocator allocator, $Type, usz len) {
	return allocator::malloc(allocator, $Type.sizeof * len);
}