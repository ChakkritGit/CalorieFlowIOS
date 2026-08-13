"""แยก layer 0 ออกมาแปลงเดี่ยว ๆ แล้วเทียบ Q/K หลัง RoPE กับ PyTorch

ทำไมต้องเล็กขนาดนี้ — โมเดลเต็มแปลงทีนึงกินเวลาหลายสิบนาทีและเคย OOM มาแล้ว
ส่วนนี้มีน้ำหนักราว 2.7M ตัว แปลงเสร็จในไม่กี่วินาที ไฟล์ไม่กี่ MB ส่งข้ามเครื่องง่าย

เหตุผลที่สงสัย RoPE — สรุปจากที่ไล่มา:

- ctx = 1 ผลตรงกับ PyTorch เป๊ะ, ctx >= 2 พังทุกกรณี
- **ที่ ctx = 1 มี key ตัวเดียว softmax ของค่าเดียวได้ 1.0 เสมอ ค่า K จึงไม่มีผล
  ต่อผลลัพธ์** ผลที่ถูกต้องที่ ctx = 1 พิสูจน์แค่เส้นทาง V ไม่ได้พิสูจน์ K
- RoPE ใส่กับ Q และ K เท่านั้น ไม่แตะ V — ความผิดพลาดใน RoPE จึงมองไม่เห็นเลย
  ที่ ctx = 1 และโผล่ทันทีที่ ctx >= 2 ซึ่งตรงกับอาการที่เจอ
- ตัดไปแล้ว: quantize (int8 พังเท่า int4), mask (ลองครบทุกแบบ), tokenizer,
  ค่าที่ใช้ปิด mask, เนื้อใน cache (ตรวจแล้วว่าถูกใช้จริง)

โครงสร้างเหมือน `StatefulQwen` ทุกอย่าง ต่างแค่มี layer เดียวและรับ hidden_states
เข้ามาตรง ๆ แทนที่จะผ่าน embedding (embedding อย่างเดียว 151936 x 1536 = 466 MB
ใหญ่เกินจะส่งข้ามเครื่อง) — cache ยังมีจริงเพราะ attention ต้องใช้ `kv_seq_len`
ในการตัดตาราง cos/sin ถ้าไม่มี cache ตารางจะสั้นกว่าตำแหน่งที่ gather แล้วหลุดขอบ

    !python /content/debug_rope.py

ได้ออกมาสองไฟล์ ให้ส่งกลับมาทั้งคู่
    /content/rope_debug.mlpackage   โมเดลเล็กสำหรับรันบนแมค
    /content/rope_reference.npz     ค่าที่ PyTorch ให้ ใช้เป็นตัวเทียบ
"""

import numpy as np
import torch
import coremltools as ct
import transformers.models.qwen2.modeling_qwen2 as qwen2_mod
from transformers import AutoModelForCausalLM
from transformers.cache_utils import Cache

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

attn = full.model.layers[0].self_attn
hidden_size = full.config.hidden_size
head_dim = hidden_size // full.config.num_attention_heads


# ── cache ตัวเดียวกับใน convert.py ย่อเหลือ layer เดียว ────────────────────
class SliceUpdateKeyValueCache(Cache):
    def __init__(self, *, k, v, max_context):
        super().__init__()
        self.past_seen_tokens = 0
        self.max_context = max_context
        self.k = k
        self.v = v

    def update(self, k_state, v_state, layer_idx, cache_kwargs=None):
        begin = self.past_seen_tokens
        end = self.past_seen_tokens + k_state.shape[-2]
        self.k[layer_idx, :, :, begin:end, :] = k_state
        self.v[layer_idx, :, :, begin:end, :] = v_state
        return self.k[layer_idx, :, :, :end, :], self.v[layer_idx, :, :, :end, :]

    def get_seq_length(self, layer_idx=0):
        return self.past_seen_tokens

    def get_max_length(self):
        return self.max_context

    def get_max_cache_shape(self):
        return self.max_context


# ── ดัก Q/K ที่ออกจาก apply_rotary_pos_emb ตัวจริง ────────────────────────
#
# ไม่เรียก apply_rotary_pos_emb เองเพราะ signature เปลี่ยนไปมาตามรุ่น (4.44 ยัง
# บังคับ position_ids ส่วนรุ่นใหม่รับ cos/sin ที่เลือกตำแหน่งมาแล้ว) — เรียก
# attention ตัวจริงแล้วดักค่าออกมาแทน ได้เส้นทางเดียวกับตอนแปลงจริงแน่นอน
_orig_apply_rope = qwen2_mod.apply_rotary_pos_emb
_captured = {}


def _spy_apply_rope(*args, **kwargs):
    q, k = _orig_apply_rope(*args, **kwargs)
    _captured["q"], _captured["k"] = q, k
    return q, k


qwen2_mod.apply_rotary_pos_emb = _spy_apply_rope


class RopeProbe(torch.nn.Module):
    """คืน Q/K หลังใส่ RoPE ของ layer 0

    ตำแหน่งคำนวณจาก `causal_mask.shape[-1] - hidden.shape[1]` เหมือน
    `StatefulQwen` ตัวจริง เพื่อให้ซับกราฟที่คำนวณตำแหน่งเหมือนกันทุกประการ
    """

    def __init__(self, attn, max_context):
        super().__init__()
        self.attn = attn
        cache_shape = (1, 1, full.config.num_key_value_heads, max_context, head_dim)
        self.register_buffer("keyCache", torch.zeros(cache_shape))
        self.register_buffer("valueCache", torch.zeros(cache_shape))
        object.__setattr__(
            self,
            "kv_cache",
            SliceUpdateKeyValueCache(
                k=self.keyCache, v=self.valueCache, max_context=max_context
            ),
        )

    def forward(self, hidden, causal_mask):
        q_len = hidden.shape[1]
        past = causal_mask.shape[-1] - q_len
        self.kv_cache.past_seen_tokens = past
        position_ids = torch.arange(past, past + q_len).unsqueeze(0)

        _captured.clear()
        self.attn(
            hidden_states=hidden,
            attention_mask=causal_mask,
            position_ids=position_ids,
            past_key_value=self.kv_cache,
            use_cache=True,
        )
        return _captured["q"], _captured["k"]


probe = RopeProbe(attn, MAX_CONTEXT).eval()

# ── ค่าอ้างอิงจาก PyTorch ──────────────────────────────────────────────────
# hidden ที่สุ่มมาถูกเก็บลง npz ไปด้วย ฝั่งแมคจึงป้อนก้อนเดียวกันเป๊ะ
# ไม่ต้องหวังพึ่งว่า RNG สองเครื่องจะให้ค่าตรงกัน
torch.manual_seed(0)
reference = {}
CASES = [(1, 1), (1, 2), (2, 2), (2, 3), (3, 3)]  # (q_len, ctx_len)

for q_len, ctx in CASES:
    hidden = torch.randn(1, q_len, hidden_size)
    mask = torch.zeros(1, 1, q_len, ctx)
    probe.keyCache.zero_()
    probe.valueCache.zero_()
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

for _m in (probe, traced):
    for _n in ("keyCache", "valueCache"):
        _buf = getattr(_m, _n, None)
        if _buf is not None:
            _buf.zero_()

query_length = ct.RangeDim(lower_bound=1, upper_bound=PREFILL_CHUNK, default=1)
context_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_CONTEXT, default=1)
cache_shape = (1, 1, full.config.num_key_value_heads, MAX_CONTEXT, head_dim)

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
    states=[
        ct.StateType(
            wrapped_type=ct.TensorType(shape=cache_shape, dtype=np.float32),
            name="keyCache",
        ),
        ct.StateType(
            wrapped_type=ct.TensorType(shape=cache_shape, dtype=np.float32),
            name="valueCache",
        ),
    ],
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT16,
    skip_model_load=True,
)
mlmodel.save("/content/rope_debug.mlpackage")
print("เซฟ /content/rope_debug.mlpackage แล้ว — ส่งกลับมาทั้งสองไฟล์")
