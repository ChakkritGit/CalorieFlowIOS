"""ตรวจว่า StatefulQwen ให้ผลตรงกับ Qwen ต้นฉบับหรือไม่ — ระดับ PyTorch ล้วน

ทำไมต้องมีไฟล์นี้: โมเดลที่แปลงแล้วพ่นข้อความไร้ความหมาย และมีผู้ต้องสงสัยสองราย
ที่แยกจากกันไม่ได้ด้วยการดูผลลัพธ์อย่างเดียว

1. ตรรกะ KV cache / mask / position ใน `StatefulQwen` ผิดตั้งแต่ต้น
2. ตรรกะถูก แต่ quantize เหลือ 4 บิตทำโมเดลพัง

ไฟล์นี้รัน wrapper ตัวเดียวกับที่ใช้แปลง เทียบกับการเรียกโมเดลแบบปกติของ
transformers ที่ fp16 ไม่ยุ่งกับ Core ML และไม่ quantize อะไรเลย

- ตรงกัน  -> ตรรกะถูก ผู้ร้ายคือ quantize ให้ไปแก้ที่ EMBEDDING_POLICY / dtype
- ไม่ตรง -> ตรรกะผิด แก้ที่ StatefulQwen ก่อน quantize ไม่ต้องแตะ

รันบน Colab เซสชันเดียวกับ convert.py (ต้องการแค่ torch + transformers)
ใช้เวลาราวสองนาที ไม่ต้องแปลงอะไรใหม่

    !python /content/verify_wrapper.py

หรือแปะทั้งไฟล์ลงเซลล์ใหม่ก็ได้ ถ้า convert.py ถูกรันในเซลล์มาแล้ว คลาส
StatefulQwen จะมีอยู่ใน namespace อยู่แล้ว — ไฟล์นี้จะใช้ตัวนั้นเลย ไม่นิยามซ้ำ
"""

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

MODEL_NAME = "Qwen/Qwen2.5-1.5B-Instruct"
MAX_CONTEXT = 2304
PREFILL_CHUNK = 128
PROMPT = "The capital of France is"

if "StatefulQwen" not in dir():
    raise SystemExit(
        "ไม่พบคลาส StatefulQwen — รัน convert.py ในเซสชันนี้ก่อน\n"
        "(หรือแปะเฉพาะส่วนนิยามคลาสมาก็ได้ ไม่ต้องรันขั้นแปลง)"
    )

# float32 ไม่ใช่ fp16 — PyTorch รัน fp16 บน CPU แล้วได้ NaN ตั้งแต่เลเยอร์ต้น ๆ
# (Colab ไม่มี GPU ในเส้นทางนี้) ไฟล์นี้ตรวจ *ตรรกะ* ไม่ได้ตรวจความแม่นของ dtype
# จึงใช้ float32 ได้โดยไม่เสียความหมายของการทดสอบ — กินแรมราว 6 GB
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float32,
    low_cpu_mem_usage=True,
    attn_implementation="eager",
)
model.eval()
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

ids = tokenizer(PROMPT, return_tensors="pt").input_ids.to(torch.int32)
print(f"prompt: {PROMPT!r}  ({ids.shape[1]} token)")


def top5(logits, label):
    # กันไม่ให้เทียบ NaN กับ NaN แล้วสรุปว่า "ตรงกัน" — topk ของ NaN ล้วนคืน
    # index เรียงตามลำดับเดิม ทุกทางจึงได้ผลเท่ากันหมดโดยไม่ได้วัดอะไรเลย
    if torch.isnan(logits).any():
        raise SystemExit(f"{label}: logits เป็น NaN — ผลเทียบไม่มีความหมาย")

    values, indices = logits.float().topk(5)
    pairs = [
        f"{tokenizer.decode([i])!r}={v:.1f}"
        for v, i in zip(values.tolist(), indices.tolist())
    ]
    print(f"{label:<28} {'  '.join(pairs)}")
    return indices.tolist()


# ── ค่าอ้างอิง: เรียก transformers แบบปกติ ไม่มี wrapper ไม่มี cache ของเรา ──
with torch.no_grad():
    reference = model(input_ids=ids.long(), use_cache=False).logits[0, -1]
ref_top = top5(reference, "อ้างอิง (transformers)")


# ── ทางที่ 1: wrapper ป้อนทั้ง prompt รอบเดียว ─────────────────────────────
def run_wrapper(chunks):
    """ป้อน prompt เป็นก้อนตามที่กำหนด แล้วคืน logits ของตำแหน่งสุดท้าย"""
    wrapper = StatefulQwen(model, MAX_CONTEXT).eval()
    wrapper.keyCache.zero_()
    wrapper.valueCache.zero_()

    past = 0
    logits = None
    with torch.no_grad():
        for chunk in chunks:
            q = chunk.shape[1]
            ctx = past + q
            # mask เหมือนที่ฝั่ง Swift สร้าง: แถว i เห็นได้ถึงคอลัมน์ past + i
            dtype = next(model.parameters()).dtype
            mask = torch.full((1, 1, q, ctx), torch.finfo(dtype).min, dtype=dtype)
            for row in range(q):
                mask[0, 0, row, : past + row + 1] = 0
            logits = wrapper(chunk, mask)
            past += q
    return logits[0, -1]


bulk = run_wrapper([ids])
bulk_top = top5(bulk, "wrapper ก้อนเดียว")

# ── ทางที่ 2: ป้อนทีละ token — เส้นทาง decode ล้วน ────────────────────────
one_by_one = [ids[:, i : i + 1] for i in range(ids.shape[1])]
seq = run_wrapper(one_by_one)
seq_top = top5(seq, "wrapper ทีละ token")

# ── ทางที่ 3: แบ่งก้อนไม่เท่ากัน — ทดสอบ prefill หลายก้อน ─────────────────
if ids.shape[1] >= 3:
    split = [ids[:, :2], ids[:, 2:]]
    split_top = top5(run_wrapper(split), "wrapper แบ่ง 2+ที่เหลือ")
else:
    split_top = ref_top

print()
# ตัวเลขสำคัญกว่าอันดับ — อันดับตรงกันได้แม้ค่าจะเพี้ยน ที่ Core ML เจอคือ
# ต่างกัน 27.9 ถ้าตรงนี้ต่างกันน้อยกว่า ~0.1 ถือว่าตรรกะเหมือนกัน
print(f"ก้อนเดียว vs อ้างอิง : ต่างสูงสุด {(bulk - reference).abs().max():.4f}")
print(f"ทีละ token vs อ้างอิง: ต่างสูงสุด {(seq - reference).abs().max():.4f}")
print()

if ref_top[0] == bulk_top[0] == seq_top[0] == split_top[0]:
    print("ตรงกันทั้งหมด -> ตรรกะ cache/mask/position ถูก")
    print("ผู้ร้ายคือขั้น quantize ให้ลอง EMBEDDING_POLICY = 'untie'")
    print("ถ้ายังพังอีก ให้เปลี่ยน dtype ของ OpLinearQuantizerConfig เป็น 'int8'")
else:
    print("ไม่ตรง -> ตรรกะใน StatefulQwen ผิด ไม่ใช่เรื่อง quantize")
    print("ดูว่าทางไหนหลุดจากค่าอ้างอิง จะชี้ได้ว่าปัญหาอยู่ที่ prefill หรือ decode")
