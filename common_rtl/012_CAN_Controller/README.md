# CAN FD Controller

## English

This folder contains the CAN FD Controller hardware design specification and its supporting reference material.

- [`VLSIT_CAN_FD_CONTROLLER_HDS.md`](VLSIT_CAN_FD_CONTROLLER_HDS.md) is the authoritative specification.
- [`CAN_FD_Controller_CSR.xlsx`](CAN_FD_Controller_CSR.xlsx) is the CSR source of truth. [`regs_canfd.json`](regs_canfd.json) is its machine-readable mirror.
- [`model/`](model/README.md) contains executable reference models. They are not RTL or an RTL testbench.
- [`research/`](research/) records protocol and reference-IP research.
- [`research/iso_11898_1_2024_technical_extract.md`](research/iso_11898_1_2024_technical_extract.md) summarizes the user-supplied ISO 11898-1:2024 technical requirements used to update the HDS.
- [`safety/`](safety/) contains the FMEDA worksheet; its inputs are assumptions, not achieved safety metrics.
- [`figures/`](figures/) contains diagrams and waveform sources/images.
- [`verification/`](verification/) contains the simulation regression (`run_regression.py`, `Makefile`), the testbenches in `tb/` and the independent frame encoder in `model/`.

**Status (2026-11-11):** RTL leaf modules and the structural top `m_canfd_top.sv` exist; the top elaborates with slang (0 errors) and has not been simulated. Lint logs are in [`lint/`](lint/). The simulation regression in [`verification/`](verification/) (`python run_regression.py`, 23 tests) covers the bit timing, stuffing, TDC and ACK tolerance units and a frame co-simulation of `m_canfd_bsp` against the independent frame encoder `verification/model/can_frame_model.py` (96 Classic and FD frames, transmit and receive). Its first run found and fixed five frame-engine defects (DEC-106); review findings F1 to F7 and F9 to F13 are in [`research/hds_rtl_review_vs_iso_2026-11-11.md`](research/hds_rtl_review_vs_iso_2026-11-11.md). The top `m_canfd_top.sv` was reworked on 2026-11-11 (rule check PASS, connections unchanged, 17 same-name connections added, DEC-107; then reset, CSR clocks and build constants DEC-108 interrupts DEC-109 and INIT/PNF DEC-110 and the CDC bundles DEC-111 DEC-112 and DEC-113 connected); 1 child input still have no driver and are listed in [`research/top_integration_open_items_2026-11-11.md`](research/top_integration_open_items_2026-11-11.md); `tools/rework_top.py` regenerates the top from the override files `tools/top_*.txt`. Not yet simulated: the whole top with two nodes, arbitration, error injection, the data phase with real bit timing, message RAM, DMA, TTCAN, power and safety. Synthesis/PPA and ISO 16845-1 conformance evidence are not claimed. Known gaps: `PARA_CANFD_TX_PREFETCH` is declared but not used by `m_canfd_txh`; `PARA_CANFD_SAF_DUP_EN` does not yet instantiate the delayed duplicate CAN core of `REQ-SAFE-010`.

## Tiếng Việt

Thư mục này chứa đặc tả thiết kế phần cứng CAN FD và các tài liệu tham chiếu hỗ trợ.

- [`VLSIT_CAN_FD_CONTROLLER_HDS.md`](VLSIT_CAN_FD_CONTROLLER_HDS.md) là đặc tả chuẩn duy nhất.
- [`CAN_FD_Controller_CSR.xlsx`](CAN_FD_Controller_CSR.xlsx) là nguồn chuẩn của bản đồ CSR. [`regs_canfd.json`](regs_canfd.json) là bản máy đọc được tương ứng.
- [`model/`](model/README.md) chứa các model tham chiếu có thể chạy. Đây không phải RTL hoặc testbench RTL.
- [`research/`](research/) lưu kết quả nghiên cứu protocol và IP tham chiếu.
- [`research/iso_11898_1_2024_technical_extract.md`](research/iso_11898_1_2024_technical_extract.md) tóm tắt yêu cầu kỹ thuật ISO 11898-1:2024 do người dùng cung cấp, được dùng để cập nhật HDS.
- [`safety/`](safety/) chứa workbook FMEDA; các đầu vào là giả định, không phải chỉ số an toàn đã đạt.
- [`figures/`](figures/) chứa sơ đồ và file nguồn/ảnh waveform.
- [`verification/`](verification/) chứa bộ regression mô phỏng (`run_regression.py`, `Makefile`), các testbench trong `tb/` và bộ mã hóa khung độc lập trong `model/`.

**Trạng thái (2026-11-11):** Các module lá RTL và top cấu trúc `m_canfd_top.sv` đã có; top biên dịch được bằng slang (0 lỗi) nhưng chưa mô phỏng. Log lint nằm trong [`lint/`](lint/). Bộ regression mô phỏng ở [`verification/`](verification/) (`python run_regression.py`, 23 test) gồm các test đơn vị cho bit timing, stuffing, TDC, dung sai ACK và co-simulation khung của `m_canfd_bsp` với bộ mã hóa khung độc lập `verification/model/can_frame_model.py` (96 khung Classic và FD, cả phát lẫn thu). Lần chạy đầu đã tìm và sửa 5 lỗi của frame engine (DEC-106); các phát hiện F1 đến F7 và F9 đến F13 nằm trong [`research/hds_rtl_review_vs_iso_2026-11-11.md`](research/hds_rtl_review_vs_iso_2026-11-11.md). Top `m_canfd_top.sv` đã được làm lại ngày 2026-11-11 (rule check PASS, kết nối cũ giữ nguyên, thêm 17 kết nối cùng tên, DEC-107; sau đó nối reset, clock CSR, hằng số build DEC-108 ngắt DEC-109 và INIT/PNF DEC-110 và các bundle CDC DEC-111 DEC-112 và DEC-113); còn 1 input của module con chưa có nguồn lái, liệt kê trong [`research/top_integration_open_items_2026-11-11.md`](research/top_integration_open_items_2026-11-11.md); `tools/rework_top.py` sinh lại top từ các file `tools/top_*.txt`. Chưa mô phỏng: toàn bộ top với hai node, phân xử, chèn lỗi, pha dữ liệu với bit timing thật, message RAM, DMA, TTCAN, nguồn và an toàn. Chưa có bằng chứng tổng hợp/PPA hay tuân thủ ISO 16845-1. Còn thiếu: `PARA_CANFD_TX_PREFETCH` đã khai báo nhưng `m_canfd_txh` chưa dùng; `PARA_CANFD_SAF_DUP_EN` chưa tạo lõi CAN dự phòng có độ trễ theo `REQ-SAFE-010`.
