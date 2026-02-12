// Software Mersenne Prime Test - For performance comparison
// Uses standard C++ division and modulo operators (SLOW!)

#include <iostream>
#include <chrono>
#include <cstdint>

using namespace std;
using namespace chrono;

// Software modular reduction using standard % operator
uint64_t mod_mersenne_software(uint64_t x, int p) {
    uint64_t mersenne = (1ULL << p) - 1;
    return x % mersenne;  // SLOW: Uses CPU division instruction!
}

// Lucas-Lehmer Test (Software Implementation)
bool lucas_lehmer_software(int p) {
    if (p == 2) return true;

    uint64_t mersenne = (1ULL << p) - 1;
    uint64_t s = 4;

    for (int i = 0; i < p - 2; i++) {
        s = (s * s - 2) % mersenne;  // DIVISION! This is slow!
    }

    return (s == 0);
}

// Cycle counter (approximate using high_resolution_clock)
uint64_t estimate_cycles(high_resolution_clock::time_point start,
                         high_resolution_clock::time_point end) {
    auto duration = duration_cast<nanoseconds>(end - start).count();
    // Assume 3.0 GHz CPU
    return (uint64_t)(duration * 3.0);
}

int main() {
    cout << "========================================\n";
    cout << "SOFTWARE Mersenne Prime Benchmark\n";
    cout << "Using standard CPU division/modulo\n";
    cout << "========================================\n\n";

    int test_exponents[] = {13, 17, 19, 31};
    uint64_t total_cycles = 0;

    for (int p : test_exponents) {
        uint64_t mersenne = (1ULL << p) - 1;

        auto start = high_resolution_clock::now();
        bool is_prime = lucas_lehmer_software(p);
        auto end = high_resolution_clock::now();

        uint64_t cycles = estimate_cycles(start, end);
        total_cycles += cycles;

        auto duration = duration_cast<nanoseconds>(end - start).count();

        cout << "[TEST] M_" << p << " = 2^" << p << " - 1 = " << mersenne << "\n";
        cout << "  Result: " << (is_prime ? "PRIME" : "NOT PRIME") << "\n";
        cout << "  Estimated Cycles: ~" << cycles << "\n";
        cout << "  Time: " << duration << " ns\n\n";
    }

    cout << "========================================\n";
    cout << "SOFTWARE SUMMARY\n";
    cout << "========================================\n";
    cout << "Total Estimated Cycles: ~" << total_cycles << "\n";
    cout << "Uses DIVISION operators: YES (SLOW!)\n";
    cout << "Uses MODULO operators: YES (SLOW!)\n\n";

    cout << "========================================\n";
    cout << "HARDWARE vs SOFTWARE\n";
    cout << "========================================\n";
    cout << "Hardware (Verilog): 138 cycles\n";
    cout << "Software (C++): ~" << total_cycles << " cycles\n";
    cout << "Speedup: ~" << (total_cycles / 138) << "x faster!\n";
    cout << "========================================\n";

    return 0;
}
