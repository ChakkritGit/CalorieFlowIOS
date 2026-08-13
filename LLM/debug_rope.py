"""แยกเฉพาะ q_proj/k_proj + RoPE ของ layer 0 ออกมาแปลงเดี่ยว ๆ แล้วเทียบกับ PyTorch

ทำไมต้องเล็กขนาดนี้ — เพราะโมเดลเต็มแปลงทีนึงกินเวลาหลายสิบนาทีและเคย OOM มาแล้ว
ส่วนนี้มีน้ำหนักราว 2.7M ตัว แปลงเสร็จในไม่กี่วินาที ไฟล์ไม่กี่ MB ส่งข้ามเครื่องง่าย

เหตุผลที่สงสัยตรงนี้ — สรุปจากที่ไล่มา:

- ctx = 1 ผลตรงกับ PyTorch เป๊ะ, ctx >= 2 พังทุกกรณี
- **ที่ ctx = 1 มี key ตัวเดียว softmax ของค่าเดียวได้ 1.0 เสมอ ค่า K จึงไม่มีผล
  ต่อผลลัพธ์** ผลที่ถูกต้องที่ ctx = 1 พิสูจน์แค่เส้นทาง V ไม่ได้พิสูจน์ K
- RoPE ใส่กับ Q และ K เท่านั้น ไม่แตะ V — ความผิดพลาดใน RoPE จึงมองไม่เห็นเลย
  ที่ ctx = 1 และโผล่ทันทีที่ ctx >= 2 ซึ่งตรงกับอาการที่เจอ
- ตัดไปแล้ว: quantize (int8 พังเท่า int4), mask (ลองครบทุกแบบ), tokenizer,
  ค่าที่ใช้ปิด mask, เนื้อใน cache (ตรวจแล้วว่าถูกใช้จริง)

รับ hidden_states เข้ามาตรง ๆ แทนที่จะผ่าน embedding เพื่อให้ไฟล์เล็กพอส่งได้
(embedding อย่างเดียว 151936 x 1536 = 466 MB) ตำแหน่งยังคำนวณจาก shape ของ
causal_mask เหมือนของจริงทุกประการ

    !python /content/debug_rope.py

ได้ออกมาสองไฟล์ ให้ส่งกลับมาทั้งคู่
    /content/rope_debug.mlpackage   โมเดลเล็กสำหรับรันบนแมค
    /content/rope_reference.npz     ค่าที่ PyTorch ให้ ใช้เป็นตัวเทียบ
"""

import numpy as np
import torch
import coremltools as ct
from transformers import AutoModelForCausalLM

MODEL_NAME = "Qwen/Qwen2.5-1.5B-Instruct"
MAX_CONTEXT = 2304
PREFILL_CHUNK = 128

print("Loading model (float32)...")
full = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float32,
    low_cpu_mem_usage=True,
    attn_implementation="eager",
)
full.eval()

layer = full.model.layers[0]
attn = layer.self_attn
rotary = attn.rotary_emb
hidden_size = full.config.hidden_size


class RopeProbe(torch.nn.Module):
    """คำนวณ Q/K หลังใส่ RoPE ของ layer 0 — เลียนแบบเส้นทางจริงทุกขั้น

    ตำแหน่งมาจาก `causal_mask.shape[-1] - hidden.shape[1]` เหมือน StatefulQwen
    ตัวจริง ไม่ได้รับ position_ids เข้ามาตรง ๆ เพราะต้องการทดสอบเส้นทางเดียวกัน
    """

    def __init__(self, attn, rotary):
        super().__init__()
        self.attn = attn
        self.rotary = rotary

    def forward(self, hidden, causal_mask):
        bsz, q_len, _ = hidden.shape
        past = causal_mask.shape[-1] - q_len
        position_ids = torch.arange(past, past + q_len).unsqueeze(0)

        q = self.attn.q_proj(hidden)
        k = self.attn.k_proj(hidden)
        q = q.view(bsz, q_len, self.attn.num_heads, self.attn.head_dim).transpose(1, 2)
        k = k.view(bsz, q_len, self.attn.num_key_value_heads, self.attn.head_dim).transpose(1, 2)

        cos, sin = self.rotary(k, position_ids)
        from transformers.models.qwen2.modeling_qwen2 import apply_rotary_pos_emb

        q, k = apply_rotary_pos_emb(q, k, cos, sin)
        return q, k


probe = RopeProbe(attn, rotary).eval()

# ── ค่าอ้างอิงจาก PyTorch ──────────────────────────────────────────────────
# hidden ที่สุ่มมาถูกเก็บลง npz ไปด้วย ฝั่งแมคจึงป้อนก้อนเดียวกันเป๊ะ
# ไม่ต้องหวังพึ่งว่า RNG สองเครื่องจะให้ค่าตรงกัน
torch.manual_seed(0)
reference = {}
CASES = [(1, 1), (1, 2), (2, 2), (2, 3), (3, 3)]  # (q_len, ctx_len)

for q_len, ctx in CASES:
    hidden = torch.randn(1, q_len, hidden_size)
    mask = torch.zeros(1, 1, q_len, ctx)
    with torch.no_grad():
        q_out, k_out = probe(hidden, mask)
    tag = f"q{q_len}_ctx{ctx}"
    reference[f"{tag}_hidden"] = hidden.numpy()
    reference[f"{tag}_q"] = q_out.numpy()
    reference[f"{tag}_k"] = k_out.numpy()
    print(f"{tag}: q{tuple(q_out.shape)} k{tuple(k_out.shape)}  |k|max={k_out.abs().max():.4f}")

np.savez("/content/rope_reference.npz", **reference)
print("\nเซฟ /content/rope_reference.npz แล้ว")

# ── แปลงเป็น Core ML ด้วยเงื่อนไขเดียวกับของจริงทุกอย่าง ───────────────────
example_hidden = torch.randn(1, 2, hidden_size)
example_mask = torch.zeros(1, 1, 2, 3)

print("Tracing...")
with torch.no_grad():
    traced = torch.jit.trace(probe, (example_hidden, example_mask))

query_length = ct.RangeDim(lower_bound=1, upper_bound=PREFILL_CHUNK, default=1)
context_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_CONTEXT, default=1)

print("Converting...")
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="hidden", shape=(1, query_length, hidden_size), dtype=np.float16),
        ct.TensorType(
            name="causal_mask",
            shape=(1, 1, query_length, context_length),
            dtype=np.float16,
        ),
    ],
    outputs=[
        ct.TensorType(name="q_rope", dtype=np.float16),
        ct.TensorType(name="k_rope", dtype=np.float16),
    ],
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT16,
    skip_model_load=True,
)
mlmodel.save("/content/rope_debug.mlpackage")
print("เซฟ /content/rope_debug.mlpackage แล้ว — ส่งกลับมาทั้งสองไฟล์")
