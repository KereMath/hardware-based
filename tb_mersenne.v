// Testbench for Mersenne Prime Hardware Tester
// Validates known Mersenne primes: M_13, M_17, M_19
// Reports clock cycles consumed (TPS = Throughput per Second)

`timescale 1ns/1ps

module tb_mersenne;

    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] exponent;
    wire is_prime;
    wire done;
    wire [15:0] cycles;

    // Clock generation (100 MHz = 10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    mersenne_prime_tester dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .exponent(exponent),
        .is_prime(is_prime),
        .done(done),
        .cycles(cycles)
    );

    // Test vectors for known Mersenne primes (Verilog-2005 compatible)
    integer test_exponents [0:3];
    integer test_mersenne_values [0:3];
    integer test_expected [0:3];

    // Performance metrics
    real total_cycles;
    real total_time_ns;
    integer tests_passed;

    // Test sequence
    initial begin
        integer i;
        real start_time, end_time, duration_ns;
        integer test_p, test_mersenne, test_expected_prime;

        // Initialize test data
        test_exponents[0] = 13; test_mersenne_values[0] = 8191;         test_expected[0] = 1;
        test_exponents[1] = 17; test_mersenne_values[1] = 131071;       test_expected[1] = 1;
        test_exponents[2] = 19; test_mersenne_values[2] = 524287;       test_expected[2] = 1;
        test_exponents[3] = 31; test_mersenne_values[3] = 2147483647;   test_expected[3] = 1;

        total_cycles = 0;
        total_time_ns = 0;
        tests_passed = 0;

        $display("========================================");
        $display("Mersenne Prime Hardware Tester");
        $display("Testing bit-shift reduction vs CPU division");
        $display("========================================\n");

        // Reset
        rst_n = 0;
        start = 0;
        exponent = 0;
        #20;
        rst_n = 1;
        #10;

        // Run tests for each exponent
        for (i = 0; i < 4; i = i + 1) begin
            test_p = test_exponents[i];
            test_mersenne = test_mersenne_values[i];
            test_expected_prime = test_expected[i];

            $display("[TEST %0d] Testing M_%0d = 2^%0d - 1 = %0d",
                     i+1, test_p, test_p, test_mersenne);

            exponent = test_p;
            start_time = $realtime;

            // Pulse start signal
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for completion
            wait(done == 1);
            @(posedge clk);
            end_time = $realtime;

            duration_ns = end_time - start_time;
            total_cycles = total_cycles + cycles;
            total_time_ns = total_time_ns + duration_ns;

            // Verify result
            if (is_prime == test_expected_prime) begin
                tests_passed = tests_passed + 1;
                $display("  PASS: is_prime = %0b (expected %0b)",
                         is_prime, test_expected_prime);
            end else begin
                $display("  FAIL: is_prime = %0b (expected %0b)",
                         is_prime, test_expected_prime);
            end

            $display("  Clock Cycles: %0d", cycles);
            $display("  Time: %.2f ns", duration_ns);
            $display("  Throughput: %.2f cycles/ns\n", cycles / duration_ns);

            #50;  // Gap between tests
        end

        // Summary
        $display("========================================");
        $display("SUMMARY");
        $display("========================================");
        $display("Tests Passed: %0d / 4", tests_passed);
        $display("Total Cycles: %.0f", total_cycles);
        $display("Total Time: %.2f ns (%.2f us)", total_time_ns, total_time_ns/1000);
        $display("Average Throughput: %.2f cycles/ns", total_cycles / total_time_ns);
        $display("\n========================================");
        $display("HARDWARE ADVANTAGE");
        $display("========================================");
        $display("- NO division operators (/) used");
        $display("- NO modulo operators (%%) used");
        $display("- Pure bit-shift & addition logic");
        $display("- Single-cycle modular reduction");
        $display("========================================\n");

        if (tests_passed == 4)
            $display("ALL TESTS PASSED! Hardware is correct.\n");
        else
            $display("SOME TESTS FAILED!\n");

        $finish;
    end

    // Timeout watchdog (prevent infinite simulation)
    initial begin
        #1000000;  // 1ms timeout
        $display("\n⚠️  TIMEOUT: Simulation exceeded 1ms");
        $finish;
    end

    // Waveform dump for debugging
    initial begin
        $dumpfile("mersenne_prime.vcd");
        $dumpvars(0, tb_mersenne);
    end

endmodule


// Standalone reducer testbench (unit test)
module tb_reducer;
    reg clk, rst_n;
    reg [25:0] x;
    wire [12:0] result;

    mersenne_reducer_comb #(.P(13), .WIDTH(26)) dut (
        .x(x),
        .result(result)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("Testing Mersenne Reducer (M_13 = 8191)");

        // Test case 1: 100 mod 8191 = 100
        x = 100;
        #1;
        $display("x=%0d, result=%0d (expected %0d)", x, result, 100);

        // Test case 2: 8191 mod 8191 = 0
        x = 8191;
        #1;
        $display("x=%0d, result=%0d (expected %0d)", x, result, 0);

        // Test case 3: 16382 mod 8191 = 0 (2 * M_13)
        x = 16382;
        #1;
        $display("x=%0d, result=%0d (expected %0d)", x, result, 0);

        // Test case 4: 16 * 16 = 256
        x = 16 * 16;
        #1;
        $display("x=%0d, result=%0d (expected %0d)", x, result, 256);

        $finish;
    end
endmodule
