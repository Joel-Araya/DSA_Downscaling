#include <iostream>
#include <cstdlib>
#include <fstream>
#include <vector>
#include <filesystem>
#include "ref_bilinear.hpp"

using namespace ref_bilinear;

int main() {

    // Directorio del proyecto (padre de build/)
    std::string base = std::filesystem::current_path().parent_path().string();
    std::string img_dir = base + "/Imagenes";

    // Scripts Python
    std::string py_gen = base + "/generate_raw.py";
    std::string py_vis = base + "/visualize.py";

    // Archivos de entrada/salida
    std::string dims_path      = img_dir + "/dims.txt";
    std::string raw_in_path    = img_dir + "/input.raw";
    std::string dims_out_path  = img_dir + "/dims_out.txt";
    std::string raw_serial_out = img_dir + "/output_serial.raw";
    std::string raw_simd_out   = img_dir + "/output_simd.raw";

    std::cout << "Working directory: " << std::filesystem::current_path() << "\n";
    std::cout << "Imagenes path: " << img_dir << "\n";

    //============================================
    // 1) Python genera la RAW
    //============================================
    std::cout << "Generando RAW con Python...\n";
    std::string cmd_gen = "python \"" + py_gen + "\" \"" + img_dir + "\"";
    system(cmd_gen.c_str());

    //============================================
    // 2) Cargar dims.txt
    //============================================
    std::ifstream dims(dims_path);
    if (!dims.is_open()) {
        std::cerr << "ERROR: No se pudo abrir dims.txt\n";
        return 1;
    }

    int w_in, h_in;
    dims >> w_in >> h_in;
    dims.close();

    //============================================
    // 3) Leer input.raw
    //============================================
    std::ifstream raw_in(raw_in_path, std::ios::binary);
    if (!raw_in.is_open()) {
        std::cerr << "ERROR: No se pudo abrir input.raw\n";
        return 1;
    }

    std::vector<uint8_t> in(w_in * h_in);
    raw_in.read((char*)in.data(), in.size());
    raw_in.close();

    double scale = 0.90;

    //============================================
    // 4) REFERENCIA SERIAL
    //============================================
    Counters c_serial;
    auto out_serial = bilinear_reference_sequential(in, w_in, h_in, scale, c_serial);

    auto dims_out_val = out_dims(w_in, h_in, scale);
    int w_out = dims_out_val.first;
    int h_out = dims_out_val.second;

    // Guardar dims_out
    std::ofstream dims_out(dims_out_path);
    dims_out << w_out << " " << h_out;
    dims_out.close();

    // Guardar RAW serial
    std::ofstream fserial(raw_serial_out, std::ios::binary);
    fserial.write((char*)out_serial.data(), out_serial.size());
    fserial.close();

    //============================================
    // 5) REFERENCIA SIMD (SIMULADA)
    //============================================
    Counters c_simd;
    int N = 16; // tamaño del bloque (igual que tu versión previa)
    auto out_simd = bilinear_reference_simd(in, w_in, h_in, scale, N, c_simd);

    // Guardar RAW SIMD
    std::ofstream fsimd(raw_simd_out, std::ios::binary);
    fsimd.write((char*)out_simd.data(), out_simd.size());
    fsimd.close();

    std::cout << "Procesamiento C++ OK.\n";

    //============================================
    // 6) Python convierte a PNG
    //============================================
    std::cout << "Generando PNG con Python...\n";
    std::string cmd_vis = "python \"" + py_vis + "\" \"" + img_dir + "\"";
    system(cmd_vis.c_str());

    std::cout << "Terminado.\n";

    //Elmininar archivos intermedios
    std::filesystem::remove(dims_path);
    //std::filesystem::remove(raw_in_path);
    std::filesystem::remove(dims_out_path);
    //std::filesystem::remove(raw_serial_out);
    //std::filesystem::remove(raw_simd_out);
    return 0;
}
