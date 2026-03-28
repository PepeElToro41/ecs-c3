import std::io;

struct TypeInfo {
	usz type_size;
	usz alignment;

	ulong component;
	String name;
}

const ulong TEST = 1 << 0;

fn void main() {
	io::printfn("Hello World! %d", (void).sizeof);
}