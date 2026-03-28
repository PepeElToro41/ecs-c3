module utils::bloom_filter;
import std::collections::bitset;


const ulong FILTER_SIZE = ulong.sizeof * 8;

struct BloomFilter {
	ulong filter_bitset;
}

// throw random sh*t at the wall
fn ulong mix(ulong element) {
	element += 0x9E3779B97F4A7C15;
	element = (element ^ (element >> 30)) * 0xBF58476D1CE4E5B9;
	element = (element ^ (element >> 27)) * 0x94D049BB133111EB;
	element = element ^ (element >> 31);
	return element;
}

fn void BloomFilter.add(&self, ulong element) {
	ulong hash1 = mix(element);
	ulong hash2 = mix(hash1);

	ulong bit1 = hash1 % FILTER_SIZE;
	ulong bit2 = hash2 % FILTER_SIZE;

	self.filter_bitset |= ((ulong)1 << bit1);
	self.filter_bitset |= ((ulong)1 << bit2);
}

fn bool BloomFilter.test(&self, BloomFilter other) @inline {
	ulong bitset = other.filter_bitset;
	return (self.filter_bitset & bitset) == bitset;
}
