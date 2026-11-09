# ISO 11898-1:2024 Technical Notes

## Purpose and source

These are concise, project-authored technical notes for the CAN controller HDS. They paraphrase protocol behavior needed by this design; they are not a full conversion, translation, or replacement for the standard.

**Source:** ISO 11898-1:2024, third edition, May 2024, supplied by the user as a local PDF. This repository retains project-authored technical paraphrases only; it does not include the source PDF.

## Phạm vi và nguồn

Đây là ghi chú kỹ thuật ngắn do dự án biên soạn để cập nhật HDS cho CAN controller. Nội dung diễn giải các hành vi protocol cần cho thiết kế; không phải bản chuyển đổi, bản dịch đầy đủ hoặc tài liệu thay thế tiêu chuẩn.

**Nguồn:** ISO 11898-1:2024, ấn bản thứ ba, tháng 5-2024, PDF do người dùng cung cấp. Repository chỉ lưu phần diễn giải kỹ thuật do dự án biên soạn, không lưu PDF gốc.

## Technical requirements relevant to this IP

### 1. Frame scope and fields

- The standard covers Classical CAN (CC), CAN FD and CAN XL. This IP targets CC and ISO FD; CAN XL and FD Light are excluded.
- CC supports 11-bit and 29-bit identifiers and up to 8 data bytes. FD supports up to 64 data bytes and uses the standard DLC mapping.
- In an FD frame, `FDF` is recessive and `res` is dominant. A receiver treats a recessive `res` as a protocol exception when exception handling is enabled; otherwise it is a form error.
- A protocol-exception event leaves the error counters unchanged, enables hard synchronization, drives recessive bits, and enters bus re-integration.

**Clauses:** §§6.6.10–6.6.11, 6.6.17.2, 6.6.7.5.

### 2. CRC, stuff count and fixed stuff

- CC uses CRC15. FD uses CRC17 for payloads up to 16 bytes and CRC21 for longer payloads. The polynomial values used in the HDS include the highest term: `0xC599`, `0x3685B` and `0x302899`.
- CC initializes its CRC register to zero. ISO FD CRC17/CRC21 initialization sets only the most-significant bit: `0x10000` and `0x100000`.
- The ISO FD stuff count is the number of dynamic stuff bits before the first fixed stuff bit, modulo eight. It is transmitted as three Gray-coded bits plus parity and checked by the receiver.
- The ISO FD CRC input includes the stuff-count field and dynamic stuff bits. Fixed stuff bits do not enter the CRC calculation. Fixed stuff bits are inserted at the positions specified for the CRC field; the total is six for CRC17 and seven for CRC21.

**Clauses:** §§6.6.4.4, 6.6.10.5, 6.6.11.5, 6.6.13.

### 3. CRC errors and error flags

- A CC receiver that detects an FCRC error does not acknowledge the frame and starts its error flag at the first EOF bit.
- An FD receiver that detects an FCRC error does not acknowledge the frame and starts its error flag after three bit-times following the CRC delimiter. Dominant bus bits between the CRC delimiter and the start of that error flag are not additional errors.
- Other listed errors start error signaling at the following bit.

**Clause:** §6.6.21.3.1. The CC and FD CRC-error cases require separate verification; one common timing rule is incorrect.

### 4. Overload signaling and final EOF bit

- Reactive overload is required for dominant during either of the first two intermission bits, dominant detected by a receiver at the last EOF bit, or dominant detected by any node at the last bit of an error or overload delimiter. A reactive overload begins one bit-time after detection.
- An LLC-requested overload can be used when receiver-internal conditions need a delay. It starts only at the first expected intermission bit and is limited to two consecutive requests. This overload type is optional to implement.
- A receiver still regards a frame as valid when the last EOF bit is dominant; that condition triggers reactive overload handling. The transmitter's own frame-validity result is separate.

**Clauses:** §§6.6.15.2, 6.6.21.3.2.

### 5. Bit timing and synchronization

For an FD-capable node that does not implement CAN XL, the HDS uses the minimum configuration ranges in Table 13:

| Parameter | Nominal bit time | FD data bit time |
|---|---:|---:|
| Shared prescaler `m` | 1–32 | Same `m` |
| SYNC_SEG | 1 tq | 1 tq |
| PROP_SEG | 1–384 tq | 0–128 tq |
| PHASE_SEG1 | 1–128 tq | 1–128 tq |
| PHASE_SEG2 | 2–128 tq | 2–128 tq |
| SJW | 1–128 tq | 1–128 tq |
| SSP offset | — | 1–160 minimum tq |

Configuration constraints: IPT is at most 2 tq; PHASE_SEG2 is at least `max(SJW, IPT)`; and SJW is at most `min(PHASE_SEG1, PHASE_SEG2)`. There is no requirement that PHASE_SEG2 be greater than or equal to PHASE_SEG1.

Synchronization permits at most one synchronization between sample points. Edge eligibility depends on the previous sampled bus value; hard synchronization and resynchronization follow the frame-state and SJW rules in §7.3.5. During bus re-integration, an optional edge filter may require two consecutive dominant nominal time quanta.

**Clauses:** §§7.3.3–7.3.5, Table 13.

### 6. Oscillator tolerance

The permitted node-clock frequency deviation is bounded around the nominal frequency. The bound depends on bit time, the configured phase segments, SJW and, for FD, the relationship between nominal and data timing. Classical CAN must satisfy formulae (3) and (4); FD must satisfy formulae (3) through (7). The standard also constrains the difference between clocks of any two nodes. A project tolerance calculator must implement the applicable profile equations; a bit-timing configuration range check alone is insufficient.

**Clause:** §7.3.6.

### 7. Fault confinement and recovery

- Error-passive state is entered when either error counter exceeds 127. Bus-off is entered when TEC exceeds 255.
- Bus-off recovery requires a software normal-mode request and 128 occurrences of 11 consecutive recessive bits. Start-up bus re-integration also uses the defined 11-recessive-bit condition.

**Clauses:** §§8.1.4–8.1.5.

## Tóm tắt kỹ thuật bằng tiếng Việt

### 1. Phạm vi frame và trường dữ liệu

IP hướng đến Classical CAN (CC) và ISO CAN FD; CAN XL nằm ngoài phạm vi. CC hỗ trợ ID 11/29 bit và tối đa 8 byte dữ liệu; FD tối đa 64 byte. Trong FD, `res` phải dominant. Nếu nhận recessive, node xử lý protocol exception khi chức năng này bật; nếu tắt thì xem là form error. Protocol exception không đổi error counter, bật hard synchronization, giữ bus recessive và đưa node vào bus re-integration.

### 2. CRC, stuff count và fixed stuff

CC dùng CRC15; ISO FD dùng CRC17 đến 16 byte và CRC21 với payload dài hơn. CRC CC khởi tạo bằng 0; CRC17/CRC21 khởi tạo lần lượt bằng `0x10000`/`0x100000`. FD truyền stuff count 3 bit Gray cộng parity, biểu diễn số dynamic stuff bit trước fixed stuff đầu tiên modulo 8. Stuff count và dynamic stuff bit được tính theo quy tắc ISO; fixed stuff bit không tham gia phép tính CRC.

### 3. CRC error và error flag

Với CRC error của CC, receiver không ACK và bắt đầu error flag tại EOF đầu tiên. Với ISO FD, receiver không ACK và bắt đầu error flag sau ba bit-time kể từ CRC delimiter; các mẫu bus dominant trong khoảng chờ không được tính thêm là error. Hai profile cần testcase riêng.

### 4. Overload và EOF cuối

Reactive overload là bắt buộc khi bus dominant ở một trong hai bit intermission đầu, khi receiver đọc dominant ở EOF cuối, hoặc khi bất kỳ node nào đọc dominant ở bit cuối của error/overload delimiter. Reactive overload bắt đầu sau một bit-time. Overload do LLC yêu cầu để trì hoãn vì bộ đệm nội bộ là tùy chọn, chỉ bắt đầu ở intermission đầu và giới hạn tối đa hai lần liên tiếp. Receiver vẫn xem frame hợp lệ khi EOF cuối dominant; khi đó nó xử lý reactive overload.

### 5. Bit timing và đồng bộ

Table 13 quy định một prescaler dùng chung cho nominal và FD data timing, cùng các dải tối thiểu được trình bày ở phần tiếng Anh. `PHASE_SEG2` phải ít nhất bằng `max(SJW, IPT)`; `SJW` không vượt quá `min(PHASE_SEG1, PHASE_SEG2)`; `IPT` tối đa 2 tq. Chuẩn không yêu cầu `PHASE_SEG2 >= PHASE_SEG1`. Đồng bộ giới hạn một lần giữa hai sample point; hard sync/resync phụ thuộc trạng thái frame, cạnh bus và SJW.

### 6. Dung sai tần số clock

Dung sai tần số node được giới hạn quanh tần số danh định. Giới hạn phụ thuộc bit-time, các phase segment, SJW và, với FD, quan hệ timing nominal/data. CC phải đạt các điều kiện trong công thức (3)–(4); FD phải đạt công thức (3)–(7). Vì vậy chỉ kiểm tra giá trị CSR nằm trong dải là chưa đủ; cần bộ tính độc lập và kiểm thử biên theo profile.

### 7. Fault confinement và bus-off recovery

Node chuyển error-passive khi TEC hoặc REC vượt 127; chuyển bus-off khi TEC vượt 255. Bus-off recovery yêu cầu phần mềm yêu cầu trở lại normal mode và bộ đếm nhận đủ 128 lần xuất hiện của chuỗi 11 bit recessive liên tiếp.

## Impact on this HDS

| HDS item | Required update |
|---|---|
| ISO frame and CRC behavior | Use REF-007 as the normative source; CRC initialization, stuff count, fixed stuff and CRC coverage are no longer open standards questions. Independent known-answer verification remains required. |
| WF-041 | The legacy figure applies one CRC-error timing to CC and FD. WF-071 now shows the profile-specific behavior. |
| Overload handling | `ovl_en` controls only optional internal-delay overload requests. Required reactive overloads must work regardless of this bit. |
| Bit-timing CSR | Current fields do not meet several Table 13 minima and expose separate nominal/data prescalers. Resolve TBD-029 before RTL generation or a full timing-conformance claim. |
| Oscillator tolerance | A separate ISO equation calculator and boundary verification are required; legacy Bosch-derived model results do not prove ISO tolerance. Resolve TBD-030. |
| Bus-off reset value | ISO requires 128 occurrences; the existing workbook resets `bo_cnt` to 129. Resolve TBD-012 or document a deliberate deviation. |
| Other profiles | Bosch non-ISO FD and TTCAN remain source-limited; this ISO document does not close those profiles. |

## Ảnh hưởng đến HDS

| Hạng mục HDS | Cập nhật cần thiết |
|---|---|
| Frame ISO và CRC | Dùng REF-007 làm nguồn chuẩn; khởi tạo CRC, stuff count, fixed stuff và phạm vi tính CRC không còn là câu hỏi chưa rõ về tiêu chuẩn. Vẫn cần kiểm chứng bằng vector độc lập. |
| WF-041 | Hình cũ dùng chung thời điểm CRC-error cho CC và FD. WF-071 thể hiện riêng hành vi từng profile. |
| Overload | `ovl_en` chỉ điều khiển overload tùy chọn do thiếu buffer nội bộ. Các reactive overload bắt buộc phải hoạt động không phụ thuộc bit này. |
| CSR bit timing | Các field hiện tại không đáp ứng một số dải tối thiểu của Table 13 và có prescaler riêng cho nominal/data. Cần chốt TBD-029 trước khi tạo RTL hoặc tuyên bố hỗ trợ đầy đủ timing. |
| Dung sai clock | Cần bộ tính phương trình ISO độc lập và kiểm thử biên; kết quả model cũ dựa trên Bosch không chứng minh dung sai ISO. Cần chốt TBD-030. |
| Bus-off reset | ISO yêu cầu 128 lần; workbook hiện reset `bo_cnt` về 129. Cần chốt TBD-012 hoặc ghi rõ đây là sai khác có chủ ý. |
| Profile khác | Bosch non-ISO FD và TTCAN vẫn thiếu nguồn chuẩn; tài liệu ISO này không đóng các profile đó. |
