module ecs::types;

struct TypeInfo {
	usz type_size;
	usz alignment;

	Entity component;
	String name;
}

alias BitFlags = ulong;
alias Entity = ulong;
alias EntityLow = ulong;
alias Component = ulong;
alias Id = ulong;
alias Pair = ulong;