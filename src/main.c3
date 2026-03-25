import std::io;


fn ulong mix(ulong element) {
	element += 0x9E3779B97F4A7C15;
	element = (element ^ (element >> 30)) * 0xBF58476D1CE4E5B9;
	element = (element ^ (element >> 27)) * 0x94D049BB133111EB;
	element = element ^ (element >> 31);
	return element;
}

fn void main() {
	ulong test = mix(6);

	io::printfn("Hello World! %d", test);

}