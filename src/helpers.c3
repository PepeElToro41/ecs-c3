module helpers;
import std::core::mem::allocator;

alias NullablePtr<Type> = Type*;
alias ArrayPtr<Type> = Type*;

fn void*? mrealloc(Allocator allocator, void* data, usz bytes, usz alignment) @inline {
	if (alignment > mem::DEFAULT_MEM_ALIGNMENT) {
		return mem::allocator::realloc_aligned(allocator, data, bytes, alignment);
	} else {
		return mem::allocator::realloc(allocator, data, bytes);
	} 
}

fn void*? malloc(Allocator allocator, usz bytes, usz alignment) @inline {
	if (alignment > mem::DEFAULT_MEM_ALIGNMENT) {
		return mem::allocator::malloc_aligned(allocator, bytes, alignment);
	} else {
		return mem::allocator::malloc(allocator, bytes);
	}
}

fn void mfree(Allocator allocator, void* data, usz alignment) @inline {
	if (alignment > mem::DEFAULT_MEM_ALIGNMENT) {
		return mem::allocator::free_aligned(allocator, data);
	} else {
		return mem::allocator::free(allocator, data);
	}
}

////////////////////////////////////////////////////////////////

macro trealloc(Allocator allocator, void* data, $Type, usz len) {
	$if $Type.alignof > mem::DEFAULT_MEM_ALIGNMENT:
		return mem::allocator::realloc_aligned(allocator, data, $Type.sizeof * len, $Type.alignof);
	$else
		return mem::allocator::realloc(allocator, data, $Type.sizeof * len);
	$endif;
}

macro talloc(Allocator allocator, $Type, usz len) {
	$if $Type.alignof > mem::DEFAULT_MEM_ALIGNMENT:
		return allocator::malloc_aligned(allocator, $Type.sizeof * len, $Type.alignof);
	$else
		return allocator::malloc(allocator, $Type.sizeof * len);
	$endif;
}

macro tfree(Allocator allocator, void* data, $Type) {
	if ($Type.alignof > mem::DEFAULT_MEM_ALIGNMENT) {
		return mem::allocator::free_aligned(allocator, data);
	} else {
		return mem::allocator::free(allocator, data);
	}
}

////////////////////////////////////////////////////////////////
