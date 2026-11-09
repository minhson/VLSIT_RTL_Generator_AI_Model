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

**Status:** RTL generation is in progress. RTL exists for reset/CDC, CRC, stuffing/destuffing, error management, bit timing, TDC, generated CSR, and the frame sequencer `rtl/m_canfd_bsp.sv`; the structural top and remaining function blocks are not complete. The BSP passes Verilator lint with 0 errors and 1 warning for unused reserved Tx-bundle bits. Its rule check has no errors and reports documentation, hierarchy, naming, and literal warnings. Full-design simulation and synthesis/PPA are deferred. No protocol-conformance claim is made.

## Tiếng Việt

Thư mục này chứa đặc tả thiết kế phần cứng CAN FD và các tài liệu tham chiếu hỗ trợ.

- [`VLSIT_CAN_FD_CONTROLLER_HDS.md`](VLSIT_CAN_FD_CONTROLLER_HDS.md) là đặc tả chuẩn duy nhất.
- [`CAN_FD_Controller_CSR.xlsx`](CAN_FD_Controller_CSR.xlsx) là nguồn chuẩn của bản đồ CSR. [`regs_canfd.json`](regs_canfd.json) là bản máy đọc được tương ứng.
- [`model/`](model/README.md) chứa các model tham chiếu có thể chạy. Đây không phải RTL hoặc testbench RTL.
- [`research/`](research/) lưu kết quả nghiên cứu protocol và IP tham chiếu.
- [`research/iso_11898_1_2024_technical_extract.md`](research/iso_11898_1_2024_technical_extract.md) tóm tắt yêu cầu kỹ thuật ISO 11898-1:2024 do người dùng cung cấp, được dùng để cập nhật HDS.
- [`safety/`](safety/) chứa workbook FMEDA; các đầu vào là giả định, không phải chỉ số an toàn đã đạt.
- [`figures/`](figures/) chứa sơ đồ và file nguồn/ảnh waveform.

**Trạng thái:** RTL đang được tạo. Hiện đã có RTL cho reset/CDC, CRC, stuffing/destuffing, quản lý lỗi, bit timing, TDC, CSR sinh tự động và bộ tuần tự frame `rtl/m_canfd_bsp.sv`; top cấu trúc cùng các khối chức năng còn lại chưa hoàn tất. BSP pass Verilator lint với 0 lỗi và 1 cảnh báo về các bit dự trữ không dùng trong Tx bundle. Rule check của BSP không có lỗi nhưng còn cảnh báo về comment, cấu trúc hierarchy, naming và literal. Mô phỏng toàn thiết kế và tổng hợp/PPA đang hoãn. Chưa có tuyên bố tuân thủ protocol.
