// ref_bilinear.hpp
// Implementación de referencia Q8.8 para interpolación bilineal
// Proporciona dos funciones:
//   - bilinear_reference_sequential(...)
//   - bilinear_reference_simd(...)
// Ambas devuelven un vector<uint8_t> con la imagen de salida.
// Counters recoge métricas simples (muls, adds, mem_reads, outputs).
//
// Uso: incluir este header en tu proyecto y llamar a las funciones desde tu
//       código que maneje I/O y comparaciones.
//
// Requiere C++11 o superior.

#ifndef REF_BILINEAR_HPP
#define REF_BILINEAR_HPP

#include <vector>
#include <cstdint>
#include <algorithm>
#include <set>
#include <utility>
#include <cmath>

namespace ref_bilinear {

    struct Counters {
        uint64_t muls = 0;        // multiplicaciones contadas (estimadas)
        uint64_t adds = 0;        // sumas contadas (estimadas)
        uint64_t mem_reads = 0;   // lecturas únicas simuladas (estimado)
        uint64_t outputs = 0;     // pixeles producidos
    };

// Clamp integer
    inline int clamp_int(int v, int lo, int hi) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    }

// Access pixel with clamp (replicate-edge)
    inline uint8_t pix_get_clamp(const std::vector<uint8_t> &img, int w, int h, int y, int x) {
        x = clamp_int(x, 0, w - 1);
        y = clamp_int(y, 0, h - 1);
        return img[y * w + x];
    }

// Compute output dims from input dims and scale (scale in (0,1])
    inline std::pair<int,int> out_dims(int w_in, int h_in, double scale) {
        int w_out = std::max(1, static_cast<int>(std::floor(w_in * scale + 1e-9)));
        int h_out = std::max(1, static_cast<int>(std::floor(h_in * scale + 1e-9)));
        return {w_out, h_out};
    }

// Sequential reference: bilinear Q8.8
// in: input image bytes (row-major), w_in,h_in
// scale: [0.5,1.0]
// counters: updated in-place
    inline std::vector<uint8_t> bilinear_reference_sequential(
            const std::vector<uint8_t> &in, int w_in, int h_in,
            double scale, Counters &counters)
    {
        auto dims = out_dims(w_in, h_in, scale);
        int w_out = dims.first;
        int h_out = dims.second;
        std::vector<uint8_t> out(static_cast<size_t>(w_out) * h_out);

        // inv_scale in Q8.8 (integer representation)
        double inv_scale_f = 1.0 / scale;
        int inv_scale_q = static_cast<int>(std::llround(inv_scale_f * 256.0)); // Q8.8

        for (int oy = 0; oy < h_out; ++oy) {
            for (int ox = 0; ox < w_out; ++ox) {
                // source position in Q8.8
                int src_x_q = ox * inv_scale_q; // Q8.8
                int src_y_q = oy * inv_scale_q;
                int ix = src_x_q >> 8;
                int iy = src_y_q >> 8;
                int fx = src_x_q & 0xFF; // fractional part (0..255)
                int fy = src_y_q & 0xFF;

                // weights (intermediate up to 65536)
                int t00 = (256 - fx) * (256 - fy);
                int t01 = fx * (256 - fy);
                int t10 = (256 - fx) * fy;
                int t11 = fx * fy;
                // convert to 0..256 by rounding (divide by 256)
                int w00 = (t00 + 128) >> 8;
                int w01 = (t01 + 128) >> 8;
                int w10 = (t10 + 128) >> 8;
                int w11 = (t11 + 128) >> 8;

                // Count weight mults (estimate)
                counters.muls += 4; // t00..t11 computations (each product)

                // read neighbors (clamped)
                uint8_t p00 = pix_get_clamp(in, w_in, h_in, iy,     ix);
                uint8_t p01 = pix_get_clamp(in, w_in, h_in, iy,     ix + 1);
                uint8_t p10 = pix_get_clamp(in, w_in, h_in, iy + 1, ix);
                uint8_t p11 = pix_get_clamp(in, w_in, h_in, iy + 1, ix + 1);

                // naive mem_reads accounting: 4 reads per output (may be redundant in practice)
                counters.mem_reads += 4;

                // pixel * weight (results in range up to 255*256)
                int r00 = static_cast<int>(p00) * w00;
                int r01 = static_cast<int>(p01) * w01;
                int r10 = static_cast<int>(p10) * w10;
                int r11 = static_cast<int>(p11) * w11;
                counters.muls += 4;

                // accumulate
                int acc = r00 + r01;
                acc += r10;
                acc += r11;
                counters.adds += 3;

                // final rounding and shift: (acc + 128) >> 8  -> integer 0..255
                int px_q8 = (acc + 128) >> 8;
                uint8_t final_px = static_cast<uint8_t>(clamp_int(px_q8, 0, 255));
                out[oy * w_out + ox] = final_px;
                counters.outputs++;
            }
        }
        return out;
    }

// Helper: collect unique source pixel coordinates (iy,ix) needed for a set of outputs.
// src_coords passed as vector of pairs (src_x_q, src_y_q) in Q8.8
    inline void collect_unique_reads_for_outputs(
            const std::vector<std::pair<int,int>> &src_coords,
            std::set<std::pair<int,int>> &unique_coords)
    {
        unique_coords.clear();
        for (const auto &sc : src_coords) {
            int src_x_q = sc.first;
            int src_y_q = sc.second;
            int ix = src_x_q >> 8;
            int iy = src_y_q >> 8;
            unique_coords.insert({iy, ix});
            unique_coords.insert({iy, ix+1});
            unique_coords.insert({iy+1, ix});
            unique_coords.insert({iy+1, ix+1});
        }
    }

// SIMD-simulated reference: processes N outputs per chunk and simulates reuse of reads.
// in: input image bytes (row-major), w_in,h_in
// scale: [0.5,1.0]
// N: simulated SIMD width (N>=1)
// counters: updated in-place
    inline std::vector<uint8_t> bilinear_reference_simd(
            const std::vector<uint8_t> &in, int w_in, int h_in,
            double scale, int N, Counters &counters)
    {
        auto dims = out_dims(w_in, h_in, scale);
        int w_out = dims.first;
        int h_out = dims.second;
        std::vector<uint8_t> out(static_cast<size_t>(w_out) * h_out);

        if (N < 1) N = 1;
        int inv_scale_q = static_cast<int>(std::llround((1.0/scale) * 256.0)); // Q8.8

        for (int oy = 0; oy < h_out; ++oy) {
            int ox = 0;
            while (ox < w_out) {
                int chunk = std::min(N, w_out - ox);
                // collect src coords Q8.8 for outputs in this chunk
                std::vector<std::pair<int,int>> src_coords;
                src_coords.reserve(chunk);
                for (int k = 0; k < chunk; ++k) {
                    int curx = ox + k;
                    int src_x_q = curx * inv_scale_q;
                    int src_y_q = oy * inv_scale_q;
                    src_coords.emplace_back(src_x_q, src_y_q);
                }
                // determine unique source pixels required by this chunk
                std::set<std::pair<int,int>> unique;
                collect_unique_reads_for_outputs(src_coords, unique);
                // simulate reading each unique pixel once
                counters.mem_reads += unique.size();

                // compute per-output results (weights, multiplications, sums)
                for (int k = 0; k < chunk; ++k) {
                    int src_x_q = src_coords[k].first;
                    int src_y_q = src_coords[k].second;
                    int ix = src_x_q >> 8;
                    int iy = src_y_q >> 8;
                    int fx = src_x_q & 0xFF;
                    int fy = src_y_q & 0xFF;

                    int t00 = (256 - fx) * (256 - fy);
                    int t01 = fx * (256 - fy);
                    int t10 = (256 - fx) * fy;
                    int t11 = fx * fy;
                    int w00 = (t00 + 128) >> 8;
                    int w01 = (t01 + 128) >> 8;
                    int w10 = (t10 + 128) >> 8;
                    int w11 = (t11 + 128) >> 8;
                    counters.muls += 4;

                    // fetch neighbors (values fetched again here but mem_reads already accounted for)
                    uint8_t p00 = pix_get_clamp(in, w_in, h_in, iy,     ix);
                    uint8_t p01 = pix_get_clamp(in, w_in, h_in, iy,     ix + 1);
                    uint8_t p10 = pix_get_clamp(in, w_in, h_in, iy + 1, ix);
                    uint8_t p11 = pix_get_clamp(in, w_in, h_in, iy + 1, ix + 1);

                    int r00 = static_cast<int>(p00) * w00;
                    int r01 = static_cast<int>(p01) * w01;
                    int r10 = static_cast<int>(p10) * w10;
                    int r11 = static_cast<int>(p11) * w11;
                    counters.muls += 4;

                    int acc = r00 + r01;
                    acc += r10;
                    acc += r11;
                    counters.adds += 3;

                    int px_q8 = (acc + 128) >> 8;
                    uint8_t final_px = static_cast<uint8_t>(clamp_int(px_q8, 0, 255));
                    out[oy * w_out + (ox + k)] = final_px;
                    counters.outputs++;
                }

                ox += chunk;
            }
        }
        return out;
    }

} // namespace ref_bilinear

#endif // REF_BILINEAR_HPP
