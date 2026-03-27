import std::io;

struct TypeInfo {
	usz type_size;
	usz alignment;

	ulong component;
	String name;
}


fn void main() {

	io::printfn("Hello World! %d %d", TypeInfo.sizeof, TypeInfo.alignof);
}