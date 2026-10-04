/*
 * Integer division helpers for armv7.
 * The iPhone 4S CPU has no divide instruction, so the compiler calls these functions for "/" and "%" with variable
 * operands (quirc needs them). The simulator-style SDK stubs do not provide them at link time, so they are built in here.
 */
#include <stdint.h>

static uint32_t tf_udivmod(uint32_t n, uint32_t d, uint32_t *rem) {
    uint32_t q = 0, r = 0;
    if (n != 0) {
        for (int i = 31 - __builtin_clz(n); i >= 0; i--) {
            r = (r << 1) | ((n >> i) & 1u);
            if (r >= d) {
                r -= d;
                q |= (1u << i);
            }
        }
    }
    if (rem) *rem = r;
    return q;
}

unsigned int __udivsi3(unsigned int a, unsigned int b) {
    return b ? tf_udivmod(a, b, 0) : 0;
}

unsigned int __umodsi3(unsigned int a, unsigned int b) {
    uint32_t r = 0;
    if (b) tf_udivmod(a, b, &r);
    return r;
}

int __divsi3(int a, int b) {
    if (b == 0) return 0;
    uint32_t ua = a < 0 ? 0u - (uint32_t)a : (uint32_t)a;
    uint32_t ub = b < 0 ? 0u - (uint32_t)b : (uint32_t)b;
    uint32_t q = tf_udivmod(ua, ub, 0);
    return ((a < 0) != (b < 0)) ? (int)(0u - q) : (int)q;
}

int __modsi3(int a, int b) {
    if (b == 0) return 0;
    uint32_t ua = a < 0 ? 0u - (uint32_t)a : (uint32_t)a;
    uint32_t ub = b < 0 ? 0u - (uint32_t)b : (uint32_t)b;
    uint32_t r = 0;
    tf_udivmod(ua, ub, &r);
    return a < 0 ? (int)(0u - r) : (int)r;
}
