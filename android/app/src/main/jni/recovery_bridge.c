#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "crapto1.h"
#include "mfkey.h"
#include "nested_util.h"


int cli_mfkey32v2(uint32_t uid, uint32_t nt0, uint32_t nr0, uint32_t ar0,
                  uint32_t nt1, uint32_t nr1, uint32_t ar1, uint64_t *out) {
    uint32_t p64 = prng_successor(nt0, 64);
    uint32_t p64b = prng_successor(nt1, 64);
    uint32_t ks2 = ar0 ^ p64;
    struct Crypto1State *s = lfsr_recovery32(ks2, 0);
    if (!s) return 0;
    struct Crypto1State *t;
    int found = 0;
    for (t = s; t->odd | t->even; ++t) {
        uint64_t key;
        lfsr_rollback_word(t, 0, 0);
        lfsr_rollback_word(t, nr0, 1);
        lfsr_rollback_word(t, uid ^ nt0, 0);
        crypto1_get_lfsr(t, &key);
        crypto1_word(t, uid ^ nt1, 0);
        crypto1_word(t, nr1, 1);
        if (ar1 == (crypto1_word(t, 0, 0) ^ p64b)) {
            *out = key;
            found = 1;
            break;
        }
    }
    free(s);
    return found;
}

int cli_mfkey64(uint32_t uid, uint32_t nt, uint32_t nr_enc, uint32_t ar_enc,
                uint32_t at_enc, uint64_t *out) {
    uint32_t p64 = prng_successor(nt, 64);
    uint32_t ks2 = ar_enc ^ p64;
    uint32_t ks3 = at_enc ^ prng_successor(p64, 32);
    struct Crypto1State *revstate = lfsr_recovery64(ks2, ks3);
    if (!revstate) return 0;
    uint64_t key;
    lfsr_rollback_word(revstate, 0, 0);
    lfsr_rollback_word(revstate, 0, 0);
    lfsr_rollback_word(revstate, nr_enc, 1);
    lfsr_rollback_word(revstate, uid ^ nt, 0);
    crypto1_get_lfsr(revstate, &key);
    crypto1_destroy(revstate);
    *out = key;
    return 1;
}

int cli_nested(uint32_t uid, uint32_t dist, const uint32_t *nts,
               const uint32_t *nt_encs, const uint32_t *pars, int count,
               uint64_t *out, int max) {
    if (count <= 0) return 0;
    size_t cap = (size_t)count * 29 + 1;
    NtpKs1 *pNK = (NtpKs1 *)malloc(sizeof(NtpKs1) * cap);
    if (!pNK) return 0;
    int j = 0;
    for (int i = 0; i < count; i++) {
        uint32_t nt1 = nts[i];
        uint32_t nt2 = nt_encs[i];
        uint8_t par_arr[3];
        uint32_t par_int = pars[i];
        for (int m = 0; m < 3; m++) par_arr[m] = (par_int >> m) & 0x01;

        uint32_t nttest = prng_successor(nt1, dist - 14);
        for (uint32_t m = dist - 14; m <= dist + 14; m++) {
            uint32_t ks1 = nt2 ^ nttest;
            if (valid_nonce(nttest, nt2, ks1, par_arr)) {
                pNK[j].ntp = nttest;
                pNK[j].ks1 = ks1;
                j++;
            }
            nttest = prng_successor(nttest, 1);
        }
    }

    uint32_t keyCount = 0;
    uint64_t *keys = nested(pNK, (uint32_t)j, uid, &keyCount);
    int copied = 0;
    if (keys != NULL) {
        copied = (int)(keyCount < (uint32_t)max ? keyCount : (uint32_t)max);
        for (int i = 0; i < copied; i++) out[i] = keys[i];
        free(keys);
    }
    free(pNK);
    return copied;
}

int cli_static_nested(uint32_t uid, uint32_t type, const uint32_t *nts,
                      const uint32_t *nt_encs, int count, uint64_t *out, int max) {
    if (count <= 0) return 0;
    uint32_t dist;
    uint32_t first = nts[0];
    if (first == 0x01200145) {
        dist = 160;
    } else if (first == 0x009080A2) {
        dist = (type == 0x61) ? 161 : 160;
    } else {
        return 0;
    }

    NtpKs1 *pNK = (NtpKs1 *)malloc(sizeof(NtpKs1) * (size_t)count);
    if (!pNK) return 0;
    for (int i = 0; i < count; i++) {
        uint32_t nttest = prng_successor(nts[i], dist);
        pNK[i].ntp = nttest;
        pNK[i].ks1 = nt_encs[i] ^ nttest;
        dist += 160;
    }

    uint32_t keyCount = 0;
    uint64_t *keys = nested(pNK, (uint32_t)count, uid, &keyCount);
    int copied = 0;
    if (keys != NULL) {
        copied = (int)(keyCount < (uint32_t)max ? keyCount : (uint32_t)max);
        for (int i = 0; i < copied; i++) out[i] = keys[i];
        free(keys);
    }
    free(pNK);
    return copied;
}

int cli_darkside(uint32_t uid, const uint32_t *nt1s, const uint64_t *ks1s,
                 const uint64_t *pars, const uint32_t *nrs, const uint32_t *ars,
                 int count, uint64_t *out, int max) {
    uint64_t *last = NULL;
    int produced = 0;
    for (int i = 0; i < count && produced < max; i++) {
        uint64_t *keys = NULL;
        uint32_t keycount = nonce2key(uid, nt1s[i], nrs[i], ars[i],
                                      pars[i], ks1s[i], &keys);
        if (keycount == 0 || keys == NULL) {
            free(keys);
            continue;
        }
        if (pars[i] == 0) {
            qsort(keys, keycount, sizeof(uint64_t), compare_uint64);
            uint32_t common = intersection(last, keys);
            if (common == 0) {
                free(last);
                last = keys;
                keys = NULL;
                continue;
            }
            for (uint32_t k = 0; k < common && produced < max; k++) out[produced++] = last[k];
            free(last);
            free(keys);
            last = NULL;
            keys = NULL;
        } else {
            for (uint32_t k = 0; k < keycount && produced < max; k++) out[produced++] = keys[k];
            free(keys);
            keys = NULL;
        }
    }
    free(last);
    return produced;
}
