"""พิมพ์ logits อ้างอิงจาก PyTorch สำหรับ token id ที่กำหนดตายตัว

ใช้เทียบกับ Core ML ทีละเคส เพื่อหาว่าโมเดลที่แปลงแล้วเริ่มหลุดจากของจริงตรงไหน

ป้อนเป็น token id ตรง ๆ ไม่ผ่าน tokenizer เพื่อตัดตัวแปรนั้นทิ้ง — id ชุดนี้มาจาก
swift-transformers ฝั่ง iOS และตรวจแล้วว่าตรงกับ HF (`"The capital of France is"`
-> [785, 6722, 315, 9625, 374])

สิ่งที่รู้แล้วตอนนี้:
- ctx = 1 (token เดียว) Core ML ให้คำตอบที่ดูสมเหตุสมผล
- ctx >= 2 พังทุกกรณี ทั้งป้อนทั้งก้อนและป้อนทีละตัว
- ไม่ใช่เรื่อง quantize (int8 พังเท่า int4) ไม่ใช่ mask (ลองครบทุกแบบ)
  ไม่ใช่ tokenizer ไม่ใช่ตำแหน่ง RoPE (สลับลำดับแล้วผลเปลี่ยนจริง)

ไฟล์นี้กิน RAM ราว 6 GB — inference อย่างเดียว ไม่ได้แปลงอะไร จึงไม่ OOM
เหมือนตอนรัน convert.py

    !python /content/reference_logits.py
"""

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

MODEL_NAME = "Qwen/Qwen2.5-1.5B-Instruct"

# float32 — fp16 บน CPU ให้ NaN กับโมเดลนี้
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float32,
    low_cpu_mem_usage=True,
    attn_implementation="eager",
)
model.eval()
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

CASES = [
    [785],
    [785, 6722],
    [785, 6722, 315],
    [785, 6722, 315, 9625, 374],
]

for ids in CASES:
    with torch.no_grad():
        logits = model(input_ids=torch.tensor([ids]), use_cache=False).logits[0, -1]

    if torch.isnan(logits).any():
        raise SystemExit("logits เป็น NaN — หยุด")

    values, indices = logits.topk(8)
    print(f"\n=== ids {ids} -> {tokenizer.decode(ids)!r} ===")
    print(f"    mean={logits.mean():.4f}  std={logits.std():.4f}  max={logits.max():.4f}")
    for v, i in zip(values.tolist(), indices.tolist()):
        print(f"    {i:>7}  {tokenizer.decode([i])!r:<14} {v:8.3f}")
