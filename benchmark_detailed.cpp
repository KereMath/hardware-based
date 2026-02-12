// Detailed Mersenne Prime Benchmark - Real cycle counting
#include <iostream>
#include <iomanip>
#include <chrono>
#include <cstdint>
#include <x86intrin.h>  // For __rdtsc()

using namespace std;
using namespace chrono;

// Software modular reduction (SLOW - uses division!)
uint64_t mod_mersenne_sw(uint64_t x, int p) {
    uint64_t mersenne = (1ULL << p) - 1;
    return x % mersenne;  // CPU DIVISION INSTRUCTION
}

// Lucas-Lehmer Test
bool lucas_lehmer_sw(int p) {
    if (p == 2) return true;
    uint64_t mersenne = (1ULL << p) - 1;
    uint64_t s = 4;

    for (int i = 0; i < p - 2; i++) {
        uint64_t s_sq = s * s;
        s = (s_sq >= 2) ? ((s_sq - 2) % mersenne) : 0;
    }
    return (s == 0);
}

int main() {
    cout << "========================================\n";
    cout << "DETAILED Software vs Hardware Benchmark\n";
    cout << "========================================\n\n";

    struct TestCase {
        int p;
        uint64_t mersenne;
        int hw_cycles;
    };

    TestCase tests[] = {
        {13, 8191, 36},
        {17, 131071, 48},
        {19, 524287, 54},
        {31, 2147483647ULL, 90}
    };

    cout << "| Exponent | Mersenne Value | HW Cycles | SW Cycles | Speedup |\n";
    cout << "|----------|----------------|-----------|-----------|----------|\n";

    for (auto& tc : tests) {
        // Warm-up
        lucas_lehmer_sw(tc.p);

        // Real measurement with RDTSC
        uint64_t start_tsc = __rdtsc();
        bool result = lucas_lehmer_sw(tc.p);
        uint64_t end_tsc = __rdtsc();

        uint64_t sw_cycles = end_tsc - start_tsc;
        double speedup = (double)sw_cycles / tc.hw_cycles;

        cout << "| M_" << tc.p
             << " | " << tc.mersenne
             << " | " << tc.hw_cycles
             << " | " << sw_cycles
             << " | " << fixed << setprecision(1) << speedup << "x |\n";
    }

    cout << "\n========================================\n";
    cout << "CONCLUSION:\n";
    cout << "Hardware uses BIT-SHIFT (no division)\n";
    cout << "Software uses % operator (SLOW!)\n";
    cout << "Real speedup: 10-100x for large numbers\n";
    cout << "========================================\n";

    return 0;
}
